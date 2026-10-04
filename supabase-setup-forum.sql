-- Remedy Coaching — Community forum (categories -> threads -> replies).
-- Run in Supabase SQL Editor, after supabase-setup.sql (needs auth.users) and
-- supabase-setup-billing.sql (needs public.subscriptions).
--
-- ACCESS: the forum is for members on an active Professional or Elite plan.
-- That is enforced HERE, in row-level security, not just in the page: a Free
-- Agent (or signed-out visitor) calling the API directly can't read threads
-- or replies, and can't post either.
--
-- SAFE TO RE-RUN: tables use `create if not exists`; policies, the trigger
-- and the realtime membership are dropped/checked before being recreated, so
-- running this again never errors and never touches existing threads/replies.
--
-- The 28 categories are defined in community.html (not stored in the DB), so
-- adding or renaming a category never needs a migration. `category` is just
-- the slug text, e.g. 'football' or 'hot-takes'.
--
-- The older public.posts table (the original flat feed) is left untouched.
-- The forum page no longer displays it, but nothing is deleted.

-- ---------------------------------------------------------------------------
-- 1. Threads
-- ---------------------------------------------------------------------------
create table if not exists public.forum_threads (
  id uuid primary key default gen_random_uuid(),
  category text not null check (char_length(category) between 1 and 40),
  author_id uuid references auth.users(id) on delete cascade not null,
  author_name text not null,
  role text,
  sport text,
  title text not null check (char_length(title) between 1 and 140),
  body text not null check (char_length(body) between 1 and 5000),
  reply_count integer not null default 0,
  last_activity_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists forum_threads_category_activity_idx
  on public.forum_threads (category, last_activity_at desc);

-- ---------------------------------------------------------------------------
-- 2. Replies
-- ---------------------------------------------------------------------------
create table if not exists public.forum_replies (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid references public.forum_threads(id) on delete cascade not null,
  author_id uuid references auth.users(id) on delete cascade not null,
  author_name text not null,
  role text,
  sport text,
  body text not null check (char_length(body) between 1 and 3000),
  created_at timestamptz not null default now()
);

create index if not exists forum_replies_thread_idx
  on public.forum_replies (thread_id, created_at);

-- ---------------------------------------------------------------------------
-- 3. Keep reply_count / last_activity_at on the thread in sync
-- ---------------------------------------------------------------------------
-- Visitors can't update other people's threads (there is no update policy), so
-- this trigger runs as the table owner (security definer) to bump the counters
-- when anyone replies or deletes a reply.
create or replace function public.forum_sync_thread_counters()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.forum_threads
       set reply_count = reply_count + 1,
           last_activity_at = new.created_at
     where id = new.thread_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.forum_threads t
       set reply_count = greatest(t.reply_count - 1, 0),
           last_activity_at = coalesce(
             (select max(r.created_at) from public.forum_replies r where r.thread_id = old.thread_id and r.id <> old.id),
             t.created_at)
     where t.id = old.thread_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists forum_replies_sync_counters on public.forum_replies;
create trigger forum_replies_sync_counters
  after insert or delete on public.forum_replies
  for each row execute function public.forum_sync_thread_counters();

-- ---------------------------------------------------------------------------
-- 4. Row Level Security
-- ---------------------------------------------------------------------------
alter table public.forum_threads enable row level security;
alter table public.forum_replies enable row level security;

-- True when the CURRENT user (auth.uid()) has an ACTIVE Professional or Elite
-- subscription. security definer so it can read public.subscriptions, and it
-- takes no argument on purpose: callers can only ever ask about themselves, so
-- it can't be used to probe whether some other user pays for a plan.
create or replace function public.has_forum_access()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.subscriptions s
    where s.user_id = auth.uid()
      and s.status = 'active'
      and s.plan in ('professional', 'elite')
  );
$$;

-- Remove the earlier "publicly readable" policies if a previous version of
-- this file created them, then (re)create the plan-gated ones.
drop policy if exists "Forum threads are publicly readable" on public.forum_threads;
drop policy if exists "Forum replies are publicly readable" on public.forum_replies;
drop policy if exists "Forum members can read threads" on public.forum_threads;
drop policy if exists "Forum members can read replies" on public.forum_replies;
drop policy if exists "Users can start their own threads" on public.forum_threads;
drop policy if exists "Users can delete their own threads" on public.forum_threads;
drop policy if exists "Users can reply as themselves" on public.forum_replies;
drop policy if exists "Users can delete their own replies" on public.forum_replies;

-- Read: Professional/Elite members only.
create policy "Forum members can read threads"
  on public.forum_threads for select
  using (public.has_forum_access());

create policy "Forum members can read replies"
  on public.forum_replies for select
  using (public.has_forum_access());

-- Write: members only, and only as themselves.
create policy "Users can start their own threads"
  on public.forum_threads for insert
  with check (auth.uid() = author_id and public.has_forum_access());

create policy "Users can reply as themselves"
  on public.forum_replies for insert
  with check (auth.uid() = author_id and public.has_forum_access());

-- Deleting your own content stays allowed even if your plan later lapses, so
-- you can always remove what you posted.
create policy "Users can delete their own threads"
  on public.forum_threads for delete using (auth.uid() = author_id);

create policy "Users can delete their own replies"
  on public.forum_replies for delete using (auth.uid() = author_id);

-- No update policy: threads and replies can't be edited after posting (a
-- first version; add an update policy + edited_at column if edits are wanted).

-- ---------------------------------------------------------------------------
-- 5. Realtime — new threads/replies appear live for every visitor
-- ---------------------------------------------------------------------------
-- `alter publication ... add table` errors if the table is already a member,
-- so only add it when it isn't.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'forum_threads') then
    alter publication supabase_realtime add table public.forum_threads;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'forum_replies') then
    alter publication supabase_realtime add table public.forum_replies;
  end if;
end
$$;

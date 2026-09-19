-- Remedy Coaching — additions for the dashboard (login + applications)
-- Run this once in your Supabase project's SQL Editor, AFTER supabase-setup.sql.
-- It only adds a new table — it does not touch profiles or posts.

-- One row per coach's application to an opportunity.
-- Opportunity data itself still lives as a constant in dashboard.html
-- (mirroring the static board on index.html), so this table just tracks
-- which coach applied to which opportunity and its status.
create table public.applications (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid references auth.users(id) on delete cascade not null,
  opportunity_id text not null,
  opportunity_title text not null,
  sport text,
  budget text,
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz default now(),
  unique (coach_id, opportunity_id)
);

alter table public.applications enable row level security;

-- Coaches can only see their own applications.
create policy "Users can view their own applications"
  on public.applications for select
  using (auth.uid() = coach_id);

-- Coaches can only apply as themselves.
create policy "Users can insert their own applications"
  on public.applications for insert
  with check (auth.uid() = coach_id);

-- Coaches can withdraw their own applications.
create policy "Users can delete their own applications"
  on public.applications for delete
  using (auth.uid() = coach_id);

-- Note: there's intentionally no public "accept/decline" policy yet — that
-- would need a client-side reviewer flow of its own. Until then, every
-- application shows as "pending" in the dashboard; status can be moved to
-- 'accepted' or 'declined' manually from the Supabase table editor.

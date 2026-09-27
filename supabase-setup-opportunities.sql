-- Remedy Coaching — real opportunities (job board), replacing the hardcoded
-- constant that previously lived in dashboard.html / index.html.
-- Run once in Supabase SQL Editor, after supabase-setup-additions.sql.
--
-- Note: applications.opportunity_id stays a plain text column (it already
-- is) and simply stores an opportunities.id (uuid) as a string going
-- forward — no foreign key at the database level, but the application code
-- only ever writes real opportunity ids into it.

create table public.opportunities (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references auth.users(id) on delete cascade not null,
  sport text not null,
  title text not null,
  description text,
  location_type text not null check (location_type in ('virtual','in_person','hybrid')),
  duration_label text,               -- e.g. "6 week project", "Season-long", "One-time clinic"
  budget_min_cents integer check (budget_min_cents > 0),
  budget_max_cents integer check (budget_max_cents >= budget_min_cents),
  status text not null default 'open' check (status in ('open','closed','filled')),
  created_at timestamptz default now()
);

alter table public.opportunities enable row level security;

-- Anyone (including signed-out visitors) can see open opportunities — this is
-- what powers the homepage job board and the coach-side "browse" list.
create policy "Open opportunities are publicly readable"
  on public.opportunities for select
  using (status = 'open');

-- A client can always see their own postings, regardless of status, so their
-- dashboard can show closed/filled ones too.
create policy "Clients can view their own opportunities"
  on public.opportunities for select
  using (auth.uid() = client_id);

create policy "Clients can post their own opportunities"
  on public.opportunities for insert
  with check (auth.uid() = client_id);

create policy "Clients can update their own opportunities"
  on public.opportunities for update
  using (auth.uid() = client_id);

create policy "Clients can delete their own opportunities"
  on public.opportunities for delete
  using (auth.uid() = client_id);

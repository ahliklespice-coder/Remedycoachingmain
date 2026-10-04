-- Remedy Coaching — 15-question "Find My Coach" quiz for athletes/parents.
-- Run once in Supabase SQL Editor, after supabase-setup.sql and
-- supabase-setup-verification.sql (the quiz surfaces the verified badge).
--
-- Two pieces:
--   1. A handful of self-reported matching fields on profiles, so a coach
--      can describe the levels/specialties/formats/rates they actually
--      offer. These are ordinary profile fields (like `bio`) — the coach
--      edits them from their own dashboard, covered by the existing
--      "Users can update their own profile" policy from supabase-setup.sql.
--      (Unlike `verified` in supabase-setup-verification.sql, there's
--      nothing here a coach shouldn't be trusted to self-report.)
--   2. match_leads — one row per "Contact this coach" click at the end of
--      the quiz, so a match actually reaches the coach instead of
--      evaporating into a client-side result page. Visible only to the
--      coach it's addressed to.

-- ---------------------------------------------------------------------------
-- 1. Self-reported matching fields (coach-editable)
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists coaching_levels text[] not null default '{}';
  -- subset of: Youth, Middle School, High School, College, Semi-Pro/Pro

alter table public.profiles
  add column if not exists specialties text[] not null default '{}';
  -- subset of: Skill Development, Strength & Conditioning, Mental Performance,
  -- Recruiting Guidance, Game Strategy, Injury Recovery, Team Building,
  -- Position-Specific Training

alter table public.profiles
  add column if not exists session_formats text[] not null default '{}';
  -- subset of: virtual, in_person, hybrid (same vocabulary as
  -- opportunities.location_type in supabase-setup-opportunities.sql)

alter table public.profiles
  add column if not exists rate_min_cents integer check (rate_min_cents is null or rate_min_cents > 0);

alter table public.profiles
  add column if not exists rate_max_cents integer;

alter table public.profiles
  drop constraint if exists profiles_rate_range_check;
alter table public.profiles
  add constraint profiles_rate_range_check
  check (rate_max_cents is null or rate_min_cents is null or rate_max_cents >= rate_min_cents);

-- ---------------------------------------------------------------------------
-- 2. match_leads — a quiz-taker's request to be connected with one coach
-- ---------------------------------------------------------------------------

create table public.match_leads (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid references auth.users(id) on delete cascade not null,
  athlete_name text not null check (char_length(athlete_name) > 0),
  athlete_email text not null check (athlete_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  sport text not null,
  level text,
  notes text,
  match_summary text,   -- human-readable "why this match" line, e.g.
                         -- "Sport match · Trains virtually · Focuses on Recruiting Guidance"
  created_at timestamptz default now()
);

alter table public.match_leads enable row level security;

-- Quiz-takers are usually NOT signed in (no account needed to take the
-- quiz), so this has to allow anonymous inserts — same reasoning as the
-- publicly-readable profiles/opportunities policies elsewhere in this repo,
-- just for insert instead of select. There is no public select policy: a
-- lead is only ever visible to the coach it names.
create policy "Anyone can submit a match lead"
  on public.match_leads for insert
  with check (true);

create policy "Coaches can view their own match leads"
  on public.match_leads for select
  using (auth.uid() = coach_id);

-- No update/delete policy yet — a coach can't mark a lead "contacted" from
-- the UI. Fine for a first version (reachable via Supabase Studio if
-- needed); worth adding a status column + update policy if that becomes
-- a real workflow.

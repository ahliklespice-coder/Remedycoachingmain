-- Remedy Coaching — real data backing for homepage "Track Record" stats
-- Run once in Supabase SQL Editor, after supabase-setup.sql and supabase-setup-additions.sql.

-- Allow applications to reach a genuine terminal "completed" state (previously
-- only pending/accepted/declined existed). "Completed" = the paid engagement
-- actually finished, as opposed to merely being accepted.
alter table public.applications drop constraint if exists applications_status_check;
alter table public.applications add constraint applications_status_check
  check (status in ('pending','accepted','declined','completed'));

-- Self-reported by the coach on their own profile.
alter table public.profiles
  add column if not exists athletes_recruited_to_college integer not null default 0
  check (athletes_recruited_to_college >= 0);

-- Real payments ledger. Empty until billing (Stripe) is wired up — the "paid to
-- coaches" stat is real from day one, it just starts at $0 rather than being
-- fabricated.
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid references auth.users(id) on delete cascade not null,
  application_id uuid references public.applications(id) on delete set null,
  amount_cents integer not null check (amount_cents > 0),
  created_at timestamptz default now()
);

alter table public.payments enable row level security;

drop policy if exists "Coaches can view their own payments" on public.payments;
create policy "Coaches can view their own payments"
  on public.payments for select
  using (auth.uid() = coach_id);

-- Public aggregate-only view for the homepage. Runs as the view owner, so it can
-- sum across all rows despite payments/applications having restrictive RLS —
-- but only ever exposes aggregate counts, never individual transactions.
create or replace view public.network_stats as
select
  (select coalesce(sum(amount_cents),0) from public.payments) as total_paid_cents,
  (select count(*) from public.applications where status = 'completed') as projects_completed,
  (select coalesce(sum(athletes_recruited_to_college),0) from public.profiles) as athletes_recruited,
  (select count(*) from public.profiles where verified = true) as verified_coaches;

grant select on public.network_stats to anon, authenticated;

-- Public per-sport coach counts, for the homepage sport tiles.
create or replace view public.sport_counts as
select sport, count(*) as coach_count
from public.profiles
group by sport;

grant select on public.sport_counts to anon, authenticated;

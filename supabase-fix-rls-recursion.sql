-- Fix: infinite RLS recursion between public.opportunities and
-- public.applications. The "Coaches can view opportunities they applied to"
-- policy (on opportunities) queries applications; applications' own
-- "Clients can view/update applications to their own opportunities" policies
-- query opportunities right back — Postgres has to evaluate each table's
-- full policy set to answer either query, looping forever.
--
-- Fix: move each cross-table check into a SECURITY DEFINER function. Such
-- functions run with the owning role's privileges (the migration role here),
-- which bypasses RLS for their internal queries — breaking the cycle
-- entirely instead of just working around it.

create or replace function public.coach_applied_to_opportunity(opp_id uuid, uid uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.applications a
    where a.opportunity_id = opp_id::text and a.coach_id = uid
  );
$$;

create or replace function public.client_owns_opportunity_for_application(app_opportunity_id text, uid uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.opportunities o
    where o.id = app_opportunity_id::uuid and o.client_id = uid
  );
$$;

create or replace function public.is_application_participant(app_id uuid, uid uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.applications a
    where a.id = app_id
      and (a.coach_id = uid or public.client_owns_opportunity_for_application(a.opportunity_id, uid))
  );
$$;

-- Re-point the three cross-table policies at the safe functions.

drop policy if exists "Coaches can view opportunities they applied to" on public.opportunities;
create policy "Coaches can view opportunities they applied to"
  on public.opportunities for select
  using (public.coach_applied_to_opportunity(id, auth.uid()));

drop policy if exists "Clients can view applications to their own opportunities" on public.applications;
create policy "Clients can view applications to their own opportunities"
  on public.applications for select
  using (public.client_owns_opportunity_for_application(opportunity_id, auth.uid()));

drop policy if exists "Clients can update applications to their own opportunities" on public.applications;
create policy "Clients can update applications to their own opportunities"
  on public.applications for update
  using (public.client_owns_opportunity_for_application(opportunity_id, auth.uid()));

drop policy if exists "Participants can view messages on their applications" on public.messages;
create policy "Participants can view messages on their applications"
  on public.messages for select
  using (public.is_application_participant(application_id, auth.uid()));

drop policy if exists "Participants can send messages on their applications" on public.messages;
create policy "Participants can send messages on their applications"
  on public.messages for insert
  with check (sender_id = auth.uid() and public.is_application_participant(application_id, auth.uid()));

-- Remedy Coaching — lets a client see and act on applications submitted to
-- their own posted opportunities. Previously only the applying coach could
-- see their own application row, so a client had no way to review or
-- respond to anyone who applied to a job they posted.

create policy "Clients can view applications to their own opportunities"
  on public.applications for select
  using (
    exists (
      select 1 from public.opportunities o
      where o.id = applications.opportunity_id::uuid
        and o.client_id = auth.uid()
    )
  );

create policy "Clients can update applications to their own opportunities"
  on public.applications for update
  using (
    exists (
      select 1 from public.opportunities o
      where o.id = applications.opportunity_id::uuid
        and o.client_id = auth.uid()
    )
  );

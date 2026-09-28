-- Remedy Coaching — direct messaging between a coach and the client on a
-- specific application. A "conversation" is scoped to one application, since
-- that's the real relationship between the two parties (a coach applied to
-- a client's posted opportunity).

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  application_id uuid references public.applications(id) on delete cascade not null,
  sender_id uuid references auth.users(id) on delete cascade not null,
  body text not null check (char_length(body) > 0 and char_length(body) <= 2000),
  created_at timestamptz default now()
);

alter table public.messages enable row level security;

-- Either the applying coach or the client who owns the opportunity being
-- applied to can read the thread.
create policy "Participants can view messages on their applications"
  on public.messages for select
  using (
    exists (
      select 1 from public.applications a
      where a.id = messages.application_id
        and (
          a.coach_id = auth.uid()
          or exists (
            select 1 from public.opportunities o
            where o.id = a.opportunity_id::uuid and o.client_id = auth.uid()
          )
        )
    )
  );

create policy "Participants can send messages on their applications"
  on public.messages for insert
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.applications a
      where a.id = messages.application_id
        and (
          a.coach_id = auth.uid()
          or exists (
            select 1 from public.opportunities o
            where o.id = a.opportunity_id::uuid and o.client_id = auth.uid()
          )
        )
    )
  );

-- Live updates so an open thread doesn't need a manual refresh.
alter publication supabase_realtime add table public.messages;

-- Without this, a coach loses visibility into an opportunity the moment its
-- client closes it (the "publicly readable" policy only covers status =
-- 'open') — which breaks messaging right when it matters most, just after
-- being accepted. This keeps the opportunity (and its client_id, for
-- displaying who you're messaging) visible to any coach who applied to it,
-- regardless of the opportunity's current status.
create policy "Coaches can view opportunities they applied to"
  on public.opportunities for select
  using (
    exists (
      select 1 from public.applications a
      where a.opportunity_id = opportunities.id::text and a.coach_id = auth.uid()
    )
  );

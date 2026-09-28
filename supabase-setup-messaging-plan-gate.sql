-- Remedy Coaching — gate sending messages to an active Professional/Elite
-- subscription, matching the pricing page's "Direct client messaging" perk.
-- Reading an existing thread is untouched (still available to both
-- participants regardless of plan) — only sending is gated, so a free-plan
-- user can see they got a message and has a reason to upgrade to reply.

create or replace function public.enforce_messaging_plan_gate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  sender_plan text;
  sender_status text;
begin
  select plan, status into sender_plan, sender_status
  from public.subscriptions
  where user_id = new.sender_id;

  if sender_plan is null or sender_status <> 'active' or sender_plan = 'free' then
    raise exception 'MESSAGING_REQUIRES_PROFESSIONAL_PLAN: Sending messages requires an active Professional or Elite plan'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_messaging_plan_gate on public.messages;
create trigger enforce_messaging_plan_gate
  before insert on public.messages
  for each row execute function public.enforce_messaging_plan_gate();

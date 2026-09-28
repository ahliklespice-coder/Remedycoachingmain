-- Remedy Coaching — enforce the Free Agent plan's "2 applications / month"
-- limit at the database level, so it can't be bypassed by calling the API
-- directly. Professional/Elite (active subscription, plan != 'free') get
-- unlimited applications, matching the pricing page.

create or replace function public.enforce_application_limit()
returns trigger
language plpgsql
security definer
as $$
declare
  coach_plan text;
  coach_status text;
  monthly_count integer;
begin
  select plan, status into coach_plan, coach_status
  from public.subscriptions
  where user_id = new.coach_id;

  -- No subscription row at all, or not an active paid plan, is treated as
  -- Free Agent.
  if coach_plan is null or coach_status <> 'active' or coach_plan = 'free' then
    select count(*) into monthly_count
    from public.applications
    where coach_id = new.coach_id
      and created_at >= date_trunc('month', now());

    if monthly_count >= 2 then
      raise exception 'FREE_PLAN_APPLICATION_LIMIT: Free Agent plan is limited to 2 applications per month'
        using errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_application_limit on public.applications;
create trigger enforce_application_limit
  before insert on public.applications
  for each row execute function public.enforce_application_limit();

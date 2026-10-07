-- Remedy Coaching — Organization accounts: sign-up, profiles, team members,
-- verification, consult invitations, and funnel analytics.
-- Run in Supabase SQL Editor, after supabase-setup-opportunities.sql,
-- supabase-setup-client-applications.sql and supabase-setup-match-quiz.sql.
--
-- SAFE TO RE-RUN: every table/column/index uses `if not exists`; functions use
-- `create or replace`; policies and triggers are dropped before being
-- recreated. Nothing here deletes or rewrites existing rows.
--
-- HOW ACCESS WORKS
--   * Organizations are created ONLY through public.create_organization()
--     (a SECURITY DEFINER function) so the org row, its owner membership and
--     its sports/expertise/needs are written atomically and validated. There
--     is deliberately no INSERT policy on public.organizations.
--   * What a member may do is stored per member in organization_members
--     .permissions (defaults derived from the role). RLS asks
--     public.org_has_perm(org, 'permission_name') — it only ever answers for
--     the CURRENT user (auth.uid()), so it can't be used to probe whether
--     someone else belongs to an organization.
--   * The base organizations table is visible to its members only. The public
--     profile page reads public.organizations_public, a view that exposes just
--     the public fields (never phone, email, street address, ZIP or notes).
--   * Cross-table checks use SECURITY DEFINER helpers (same fix as
--     supabase-fix-rls-recursion.sql) so policies never recurse.

-- ---------------------------------------------------------------------------
-- 1. Catalogs: sports and the expertise areas that belong to each sport
-- ---------------------------------------------------------------------------
create table if not exists public.sports (
  id smallserial primary key,
  name text not null unique,
  sort_order smallint not null default 0
);

create table if not exists public.expertise (
  id serial primary key,
  sport_id smallint not null references public.sports(id) on delete cascade,
  name text not null,
  -- Which of the broad coach specialties (profiles.specialties) this expertise
  -- area maps to, so organization needs can be matched to coach profiles.
  coach_specialty text,
  unique (sport_id, name)
);

alter table public.sports enable row level security;
alter table public.expertise enable row level security;

drop policy if exists "Sports are publicly readable" on public.sports;
create policy "Sports are publicly readable" on public.sports for select using (true);
drop policy if exists "Expertise is publicly readable" on public.expertise;
create policy "Expertise is publicly readable" on public.expertise for select using (true);

insert into public.sports (name, sort_order) values
  ('Football',1),('Basketball',2),('Baseball',3),('Soccer',4),('Wrestling',5),
  ('Track & Field',6),('Volleyball',7),('Lacrosse',8),('Tennis',9),('Swimming',10),
  ('Hockey',11),('Cheerleading',12),('Martial Arts',13),('Strength & Conditioning',14),
  ('Pickleball',15),('Other',16)
on conflict (name) do nothing;

insert into public.expertise (sport_id, name, coach_specialty)
select s.id, v.name, v.cs
from (values
  ('Football','Offensive Strategy','Game Strategy'),
  ('Football','Defensive Strategy','Game Strategy'),
  ('Football','Quarterback Development','Position-Specific Training'),
  ('Football','Wide Receiver Development','Position-Specific Training'),
  ('Football','Offensive Line','Position-Specific Training'),
  ('Football','Defensive Line','Position-Specific Training'),
  ('Football','Recruiting','Recruiting Guidance'),
  ('Football','Strength & Conditioning','Strength & Conditioning'),
  ('Football','Film Analysis','Game Strategy'),
  ('Football','Program Development','Team Building'),
  ('Football','Coaching Development','Team Building'),

  ('Basketball','Shooting Development','Skill Development'),
  ('Basketball','Ball Handling','Skill Development'),
  ('Basketball','Offensive Systems','Game Strategy'),
  ('Basketball','Defensive Systems','Game Strategy'),
  ('Basketball','Post Play','Position-Specific Training'),
  ('Basketball','Guard Play','Position-Specific Training'),
  ('Basketball','Recruiting','Recruiting Guidance'),
  ('Basketball','Strength & Conditioning','Strength & Conditioning'),
  ('Basketball','Film Analysis','Game Strategy'),
  ('Basketball','Program Development','Team Building'),

  ('Baseball','Hitting','Skill Development'),
  ('Baseball','Pitching','Position-Specific Training'),
  ('Baseball','Catching','Position-Specific Training'),
  ('Baseball','Infield Defense','Position-Specific Training'),
  ('Baseball','Outfield Defense','Position-Specific Training'),
  ('Baseball','Base Running','Skill Development'),
  ('Baseball','Recruiting','Recruiting Guidance'),
  ('Baseball','Strength & Conditioning','Strength & Conditioning'),
  ('Baseball','Analytics & Film','Game Strategy'),
  ('Baseball','Program Development','Team Building'),

  ('Soccer','Technical Skills','Skill Development'),
  ('Soccer','Attacking Tactics','Game Strategy'),
  ('Soccer','Defending Tactics','Game Strategy'),
  ('Soccer','Goalkeeping','Position-Specific Training'),
  ('Soccer','Recruiting','Recruiting Guidance'),
  ('Soccer','Strength & Conditioning','Strength & Conditioning'),
  ('Soccer','Film Analysis','Game Strategy'),
  ('Soccer','Youth Development','Skill Development'),
  ('Soccer','Program Development','Team Building'),

  ('Wrestling','Technique Development','Skill Development'),
  ('Wrestling','Takedowns','Skill Development'),
  ('Wrestling','Escapes','Skill Development'),
  ('Wrestling','Top Position','Skill Development'),
  ('Wrestling','Bottom Position','Skill Development'),
  ('Wrestling','Conditioning','Strength & Conditioning'),
  ('Wrestling','Recruiting','Recruiting Guidance'),
  ('Wrestling','Tournament Preparation','Game Strategy'),
  ('Wrestling','Youth Development','Skill Development'),
  ('Wrestling','Program Development','Team Building'),

  ('Track & Field','Sprints','Position-Specific Training'),
  ('Track & Field','Distance','Position-Specific Training'),
  ('Track & Field','Hurdles','Position-Specific Training'),
  ('Track & Field','Jumps','Position-Specific Training'),
  ('Track & Field','Throws','Position-Specific Training'),
  ('Track & Field','Relays','Skill Development'),
  ('Track & Field','Recruiting','Recruiting Guidance'),
  ('Track & Field','Strength & Conditioning','Strength & Conditioning'),
  ('Track & Field','Meet Preparation','Game Strategy'),
  ('Track & Field','Program Development','Team Building'),

  ('Volleyball','Setting','Position-Specific Training'),
  ('Volleyball','Hitting','Skill Development'),
  ('Volleyball','Serving & Passing','Skill Development'),
  ('Volleyball','Defense','Skill Development'),
  ('Volleyball','Rotations & Strategy','Game Strategy'),
  ('Volleyball','Recruiting','Recruiting Guidance'),
  ('Volleyball','Strength & Conditioning','Strength & Conditioning'),
  ('Volleyball','Film Analysis','Game Strategy'),
  ('Volleyball','Program Development','Team Building'),

  ('Lacrosse','Attack','Position-Specific Training'),
  ('Lacrosse','Midfield','Position-Specific Training'),
  ('Lacrosse','Defense','Position-Specific Training'),
  ('Lacrosse','Goalkeeping','Position-Specific Training'),
  ('Lacrosse','Face-offs','Position-Specific Training'),
  ('Lacrosse','Recruiting','Recruiting Guidance'),
  ('Lacrosse','Strength & Conditioning','Strength & Conditioning'),
  ('Lacrosse','Film Analysis','Game Strategy'),
  ('Lacrosse','Program Development','Team Building'),

  ('Tennis','Stroke Technique','Skill Development'),
  ('Tennis','Serve Development','Skill Development'),
  ('Tennis','Match Strategy','Game Strategy'),
  ('Tennis','Doubles Play','Game Strategy'),
  ('Tennis','Mental Game','Mental Performance'),
  ('Tennis','Recruiting','Recruiting Guidance'),
  ('Tennis','Strength & Conditioning','Strength & Conditioning'),
  ('Tennis','Program Development','Team Building'),

  ('Swimming','Stroke Technique','Skill Development'),
  ('Swimming','Starts & Turns','Skill Development'),
  ('Swimming','Distance Training','Skill Development'),
  ('Swimming','Sprint Training','Skill Development'),
  ('Swimming','Meet Preparation','Game Strategy'),
  ('Swimming','Dryland Training','Strength & Conditioning'),
  ('Swimming','Recruiting','Recruiting Guidance'),
  ('Swimming','Youth Development','Skill Development'),
  ('Swimming','Program Development','Team Building'),

  ('Hockey','Skating','Skill Development'),
  ('Hockey','Shooting','Skill Development'),
  ('Hockey','Offensive Systems','Game Strategy'),
  ('Hockey','Defensive Systems','Game Strategy'),
  ('Hockey','Goaltending','Position-Specific Training'),
  ('Hockey','Recruiting','Recruiting Guidance'),
  ('Hockey','Strength & Conditioning','Strength & Conditioning'),
  ('Hockey','Film Analysis','Game Strategy'),
  ('Hockey','Program Development','Team Building'),

  ('Cheerleading','Stunting','Skill Development'),
  ('Cheerleading','Tumbling','Skill Development'),
  ('Cheerleading','Jumps','Skill Development'),
  ('Cheerleading','Routine Choreography','Skill Development'),
  ('Cheerleading','Safety & Spotting','Skill Development'),
  ('Cheerleading','Competition Preparation','Game Strategy'),
  ('Cheerleading','Flexibility & Conditioning','Strength & Conditioning'),
  ('Cheerleading','Program Development','Team Building'),

  ('Martial Arts','Technique Development','Skill Development'),
  ('Martial Arts','Sparring','Skill Development'),
  ('Martial Arts','Forms & Kata','Skill Development'),
  ('Martial Arts','Competition Preparation','Game Strategy'),
  ('Martial Arts','Conditioning','Strength & Conditioning'),
  ('Martial Arts','Mental Discipline','Mental Performance'),
  ('Martial Arts','Youth Development','Skill Development'),
  ('Martial Arts','Program Development','Team Building'),

  ('Strength & Conditioning','Speed & Agility','Strength & Conditioning'),
  ('Strength & Conditioning','Strength Programming','Strength & Conditioning'),
  ('Strength & Conditioning','Olympic Lifts','Strength & Conditioning'),
  ('Strength & Conditioning','Injury Prevention','Injury Recovery'),
  ('Strength & Conditioning','Return to Play','Injury Recovery'),
  ('Strength & Conditioning','Program Development','Team Building'),
  ('Strength & Conditioning','Coaching Development','Team Building'),

  ('Pickleball','Stroke Technique','Skill Development'),
  ('Pickleball','Doubles Strategy','Game Strategy'),
  ('Pickleball','Mental Game','Mental Performance'),
  ('Pickleball','Program Development','Team Building'),

  ('Other','Skill Development','Skill Development'),
  ('Other','Program Development','Team Building'),
  ('Other','Coaching Development','Team Building'),
  ('Other','Recruiting','Recruiting Guidance'),
  ('Other','Strength & Conditioning','Strength & Conditioning')
) as v(sport, name, cs)
join public.sports s on s.name = v.sport
on conflict (sport_id, name) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Small helpers
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- "https://www.Example.com/athletics?x=1" -> "example.com", used to stop two
-- accounts being created for the same organization website.
create or replace function public.normalize_domain(url text)
returns text language sql immutable as $$
  select nullif(
    regexp_replace(
      regexp_replace(
        regexp_replace(lower(trim(coalesce(url, ''))), '^[a-z][a-z0-9+.-]*://', ''),
        '^www\.', ''),
      '[/?#:].*$', ''),
    '');
$$;

-- Default permissions for each role. A member's own permissions column is what
-- RLS reads, so an owner can later tune an individual member if needed.
create or replace function public.org_role_permissions(r text)
returns jsonb language sql immutable as $$
  select case r
    when 'owner'          then '{"manage_org":true,"manage_members":true,"post_opportunities":true,"manage_applicants":true,"contact_coaches":true}'::jsonb
    when 'admin'          then '{"manage_org":true,"manage_members":true,"post_opportunities":true,"manage_applicants":true,"contact_coaches":true}'::jsonb
    when 'hiring_manager' then '{"manage_org":false,"manage_members":false,"post_opportunities":true,"manage_applicants":true,"contact_coaches":true}'::jsonb
    else                       '{"manage_org":false,"manage_members":false,"post_opportunities":false,"manage_applicants":false,"contact_coaches":false}'::jsonb
  end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Organizations
-- ---------------------------------------------------------------------------
create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  organization_name text not null check (char_length(organization_name) between 2 and 120),
  organization_type text not null check (organization_type in (
    'High School','Middle School','College / University','Professional Sports Organization',
    'Youth Sports Organization','Travel / Club Team','Athletic Department','Sports Camp',
    'Training Facility','Nonprofit','Sports Business','Community Organization',
    'Individual Team','Other')),
  description text check (description is null or char_length(description) <= 1000),
  website text check (website is null or char_length(website) <= 300),
  normalized_domain text,
  email text check (email is null or char_length(email) <= 200),
  phone text check (phone is null or char_length(phone) <= 40),
  logo_url text check (logo_url is null or char_length(logo_url) <= 500),
  address text check (address is null or char_length(address) <= 200),
  city text check (city is null or char_length(city) <= 80),
  state text check (state is null or char_length(state) <= 40),
  zip text check (zip is null or char_length(zip) <= 20),
  country text not null default 'United States' check (char_length(country) <= 60),
  employee_count text check (employee_count is null or employee_count in ('1–10','11–25','26–50','51–100','101–250','251–500','500+')),
  athlete_count text check (athlete_count is null or athlete_count in ('1–10','11–25','26–50','51–100','101–250','251–500','500+')),
  preferred_format text check (preferred_format is null or preferred_format in ('virtual','in_person','either')),
  budget_min_cents integer check (budget_min_cents is null or budget_min_cents > 0),
  budget_max_cents integer check (budget_max_cents is null or budget_max_cents > 0),
  verification_status text not null default 'unverified'
    check (verification_status in ('unverified','pending','verified','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Duplicate protection: one account per website domain, and one per
-- (name, city, state).
create unique index if not exists organizations_domain_uniq
  on public.organizations (normalized_domain) where normalized_domain is not null;
create unique index if not exists organizations_name_place_uniq
  on public.organizations (lower(organization_name), lower(coalesce(city,'')), lower(coalesce(state,'')));

create or replace function public.organizations_before_write()
returns trigger language plpgsql as $$
begin
  new.normalized_domain := public.normalize_domain(new.website);

  if tg_op = 'UPDATE' then
    -- Verification status and ownership are never self-service. Only a
    -- SECURITY DEFINER function that sets the flag below, or the service role
    -- (admin review), may change them.
    if coalesce(auth.role(), '') = 'authenticated'
       and coalesce(current_setting('remedy.allow_org_protected_change', true), '') <> '1' then
      new.verification_status := old.verification_status;
      new.owner_id := old.owner_id;
    end if;
    new.updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists organizations_before_write on public.organizations;
create trigger organizations_before_write
  before insert or update on public.organizations
  for each row execute function public.organizations_before_write();

create table if not exists public.organization_sports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sport_id smallint not null references public.sports(id),
  custom_name text check (custom_name is null or char_length(custom_name) <= 60),
  unique (organization_id, sport_id)
);

create table if not exists public.organization_expertise (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  expertise_id integer not null references public.expertise(id),
  unique (organization_id, expertise_id)
);

create table if not exists public.organization_needs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  need_type text not null check (need_type in (
    'Player Development','Team Development','Coaching Development','Recruiting',
    'Program Development','Practice Planning','Game Strategy','Film Analysis',
    'Strength & Conditioning','Leadership','Team Culture','Youth Development',
    'Staff Training','Tournament Preparation','Athletic Program Evaluation','Other')),
  custom_text text check (custom_text is null or char_length(custom_text) <= 120),
  unique (organization_id, need_type)
);

-- ---------------------------------------------------------------------------
-- 4. Members and roles
-- ---------------------------------------------------------------------------
create table if not exists public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'viewer'
    check (role in ('owner','admin','staff','hiring_manager','viewer')),
  permissions jsonb not null default '{}'::jsonb,
  display_name text check (display_name is null or char_length(display_name) <= 120),
  job_title text check (job_title is null or char_length(job_title) <= 120),
  created_at timestamptz not null default now(),
  unique (organization_id, user_id)
);

create index if not exists organization_members_user_idx on public.organization_members (user_id);

-- Internal, uid-parameterised check. Execute is REVOKED from API roles below;
-- only other SECURITY DEFINER functions (which run as the owner) can call it.
create or replace function public._org_has_perm(org uuid, uid uuid, perm text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.organization_members m
    where m.organization_id = org and m.user_id = uid
      and coalesce((m.permissions ->> perm)::boolean, false)
  );
$$;

-- Public wrappers: each answers only about the CURRENT user.
create or replace function public.org_is_member(org uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.organization_members m
                 where m.organization_id = org and m.user_id = auth.uid());
$$;

create or replace function public.org_has_perm(org uuid, perm text)
returns boolean language sql stable security definer set search_path = public as $$
  select public._org_has_perm(org, auth.uid(), perm);
$$;

create or replace function public.org_is_owner(org uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.organization_members m
                 where m.organization_id = org and m.user_id = auth.uid() and m.role = 'owner');
$$;

revoke all on function public._org_has_perm(uuid, uuid, text) from public, anon, authenticated;

create or replace function public.org_members_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  org_exists boolean;
  other_owners integer;
  acting uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    if new.permissions = '{}'::jsonb then
      new.permissions := public.org_role_permissions(new.role);
    end if;
    return new;
  end if;

  -- UPDATE / DELETE guards. Skipped when the parent organization (or user) is
  -- already gone — i.e. this row is being removed by a cascade.
  select exists (select 1 from public.organizations where id = old.organization_id) into org_exists;
  if not org_exists then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'UPDATE' then
    if new.organization_id <> old.organization_id or new.user_id <> old.user_id then
      raise exception 'IMMUTABLE_FIELDS: membership organization and user cannot change';
    end if;
    if new.role <> old.role then
      new.permissions := public.org_role_permissions(new.role);
    end if;
  end if;

  if acting is not null and coalesce(auth.role(), '') = 'authenticated' then
    -- Only owners may grant, revoke, or change an owner or an admin.
    if (tg_op = 'DELETE' and old.user_id <> acting and old.role in ('owner','admin'))
       or (tg_op = 'UPDATE' and new.role <> old.role and (old.role in ('owner','admin') or new.role in ('owner','admin'))) then
      if not public.org_is_owner(old.organization_id) then
        raise exception 'OWNER_REQUIRED: only an organization owner can change owners or admins';
      end if;
    end if;
  end if;

  -- An organization must always keep at least one owner.
  if old.role = 'owner' and (tg_op = 'DELETE' or new.role <> 'owner') then
    select count(*) into other_owners from public.organization_members
      where organization_id = old.organization_id and role = 'owner' and id <> old.id;
    if other_owners = 0 then
      raise exception 'LAST_OWNER: an organization must keep at least one owner';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists org_members_before_write on public.organization_members;
create trigger org_members_before_write
  before insert or update or delete on public.organization_members
  for each row execute function public.org_members_before_write();

-- ---------------------------------------------------------------------------
-- 5. Invitations (shared by link — accepted by the invited email's account)
-- ---------------------------------------------------------------------------
create table if not exists public.organization_invites (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  email text not null check (position('@' in email) > 1 and char_length(email) <= 200),
  role text not null check (role in ('admin','staff','hiring_manager','viewer')),
  invited_by uuid references auth.users(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','accepted','revoked')),
  created_at timestamptz not null default now(),
  accepted_at timestamptz
);

create unique index if not exists organization_invites_pending_uniq
  on public.organization_invites (organization_id, lower(email)) where status = 'pending';

-- ---------------------------------------------------------------------------
-- 6. Verification requests (optional trust badge)
-- ---------------------------------------------------------------------------
create table if not exists public.organization_verification_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  requested_by uuid references auth.users(id) on delete set null,
  website_url text check (website_url is null or char_length(website_url) <= 300),
  email_domain text check (email_domain is null or char_length(email_domain) <= 120),
  registration_info text check (registration_info is null or char_length(registration_info) <= 1000),
  athletic_dept_info text check (athletic_dept_info is null or char_length(athletic_dept_info) <= 1000),
  district_info text check (district_info is null or char_length(district_info) <= 1000),
  social_url text check (social_url is null or char_length(social_url) <= 300),
  document_paths text[] not null default '{}',
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewer_note text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create unique index if not exists org_verification_one_pending
  on public.organization_verification_requests (organization_id) where status = 'pending';

-- Submitting a request flips the organization to 'pending'. Done in a
-- SECURITY DEFINER trigger with the protected-change flag set, since members
-- can't edit verification_status themselves.
create or replace function public.org_verification_requested()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform set_config('remedy.allow_org_protected_change', '1', true);
  update public.organizations set verification_status = 'pending'
    where id = new.organization_id and verification_status <> 'verified';
  perform set_config('remedy.allow_org_protected_change', '', true);
  return new;
end;
$$;

drop trigger if exists org_verification_requested on public.organization_verification_requests;
create trigger org_verification_requested
  after insert on public.organization_verification_requests
  for each row execute function public.org_verification_requested();

-- ---------------------------------------------------------------------------
-- 7. Consult invitations (org -> coach) and public inquiries (coach -> org)
-- ---------------------------------------------------------------------------
create table if not exists public.consult_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  coach_id uuid not null references auth.users(id) on delete cascade,
  invited_by uuid references auth.users(id) on delete set null,
  kind text not null check (kind in ('consult','message')),
  message text not null check (char_length(message) between 1 and 1000),
  opportunity_id uuid references public.opportunities(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  response_message text check (response_message is null or char_length(response_message) <= 1000),
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

create unique index if not exists consult_invitations_pending_uniq
  on public.consult_invitations (organization_id, coach_id, kind) where status = 'pending';

create or replace function public.consult_invitations_before_update()
returns trigger language plpgsql as $$
begin
  if coalesce(auth.role(), '') = 'authenticated' then
    if new.organization_id <> old.organization_id or new.coach_id <> old.coach_id
       or new.invited_by is distinct from old.invited_by or new.kind <> old.kind
       or new.message <> old.message or new.opportunity_id is distinct from old.opportunity_id then
      raise exception 'IMMUTABLE_FIELDS: only the response can change';
    end if;
    if new.status <> old.status then new.responded_at := now(); end if;
  end if;
  return new;
end;
$$;

drop trigger if exists consult_invitations_before_update on public.consult_invitations;
create trigger consult_invitations_before_update
  before update on public.consult_invitations
  for each row execute function public.consult_invitations_before_update();

create table if not exists public.organization_inquiries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  from_user_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (char_length(message) between 1 and 1000),
  created_at timestamptz not null default now()
);

-- Light spam control: at most 5 inquiries per user per day, 2 per organization.
create or replace function public.organization_inquiries_rate_limit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.organization_inquiries
        where from_user_id = new.from_user_id and created_at > now() - interval '1 day') >= 5 then
    raise exception 'RATE_LIMITED: too many inquiries today';
  end if;
  if (select count(*) from public.organization_inquiries
        where from_user_id = new.from_user_id and organization_id = new.organization_id
          and created_at > now() - interval '1 day') >= 2 then
    raise exception 'RATE_LIMITED: you already contacted this organization today';
  end if;
  return new;
end;
$$;

drop trigger if exists organization_inquiries_rate_limit on public.organization_inquiries;
create trigger organization_inquiries_rate_limit
  before insert on public.organization_inquiries
  for each row execute function public.organization_inquiries_rate_limit();

-- ---------------------------------------------------------------------------
-- 8. Funnel analytics (marketing automation / retargeting later)
-- ---------------------------------------------------------------------------
-- Anyone may append an event about themselves; nobody can read the table with
-- an API key (query it with the service role / SQL editor). `anonymous_id`
-- ties pre-signup events to the account created afterwards. `dedupe_key`
-- makes one-time milestones (signup completed, email verified, ...) idempotent.
create table if not exists public.analytics_events (
  id uuid primary key default gen_random_uuid(),
  event_name text not null check (event_name ~ '^[a-z][a-z0-9_]{2,59}$'),
  user_id uuid references auth.users(id) on delete set null,
  organization_id uuid references public.organizations(id) on delete set null,
  anonymous_id text check (anonymous_id is null or char_length(anonymous_id) <= 64),
  properties jsonb not null default '{}'::jsonb check (pg_column_size(properties) < 4096),
  dedupe_key text unique check (dedupe_key is null or char_length(dedupe_key) <= 160),
  created_at timestamptz not null default now()
);

create index if not exists analytics_events_name_time_idx on public.analytics_events (event_name, created_at desc);
create index if not exists analytics_events_org_idx on public.analytics_events (organization_id);

-- A coach being accepted for an organization's opportunity is "coach hired".
-- A trigger records it no matter which page made the change.
create or replace function public.track_coach_hired()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  org uuid;
begin
  if new.status = 'accepted' and old.status is distinct from 'accepted' then
    select o.organization_id into org from public.opportunities o where o.id::text = new.opportunity_id;
    insert into public.analytics_events (event_name, user_id, organization_id, properties, dedupe_key)
    values ('coach_hired', auth.uid(), org,
            jsonb_build_object('application_id', new.id, 'coach_id', new.coach_id, 'opportunity_id', new.opportunity_id),
            'coach_hired:' || new.id)
    on conflict (dedupe_key) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists track_coach_hired on public.applications;
create trigger track_coach_hired
  after update of status on public.applications
  for each row execute function public.track_coach_hired();

-- ---------------------------------------------------------------------------
-- 9. Opportunities: link to an organization, drafts, and richer fields
-- ---------------------------------------------------------------------------
alter table public.opportunities add column if not exists organization_id uuid references public.organizations(id) on delete set null;
alter table public.opportunities add column if not exists expertise_needed text[] not null default '{}';
alter table public.opportunities add column if not exists start_date date;
alter table public.opportunities add column if not exists application_deadline date;
alter table public.opportunities add column if not exists experience_requirements text check (experience_requirements is null or char_length(experience_requirements) <= 600);
alter table public.opportunities add column if not exists location_text text check (location_text is null or char_length(location_text) <= 120);
alter table public.opportunities add column if not exists published_at timestamptz;

alter table public.opportunities drop constraint if exists opportunities_status_check;
alter table public.opportunities add constraint opportunities_status_check
  check (status in ('draft','open','closed','filled'));

create index if not exists opportunities_org_idx on public.opportunities (organization_id);

-- Only an account with a verified email may publish. (Unverified accounts can
-- already not sign in while email confirmation is on; this is the safety net.)
create or replace function public.opportunities_publish_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'open' and auth.uid() is not null
     and (tg_op = 'INSERT' or old.status is distinct from 'open') then
    if not exists (select 1 from auth.users u where u.id = auth.uid() and u.email_confirmed_at is not null) then
      raise exception 'EMAIL_NOT_VERIFIED: verify your email before publishing an opportunity';
    end if;
    if new.published_at is null then new.published_at := now(); end if;
  end if;
  return new;
end;
$$;

drop trigger if exists opportunities_publish_guard on public.opportunities;
create trigger opportunities_publish_guard
  before insert or update on public.opportunities
  for each row execute function public.opportunities_publish_guard();

-- Organization hiring managers (not just the original poster) can manage an
-- organization's applicants. Everything that already asks "does this client own
-- the opportunity?" (applications RLS, messages) gets this for free.
create or replace function public.client_owns_opportunity_for_application(app_opportunity_id text, uid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.opportunities o
    where o.id = app_opportunity_id::uuid
      and (o.client_id = uid
           or (o.organization_id is not null
               and public._org_has_perm(o.organization_id, uid, 'manage_applicants')))
  );
$$;

-- ---------------------------------------------------------------------------
-- 10. Coach profile fields organizations can search on
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists headline text check (headline is null or char_length(headline) <= 120);
alter table public.profiles add column if not exists years_experience integer check (years_experience is null or years_experience between 0 and 60);
alter table public.profiles add column if not exists city text check (city is null or char_length(city) <= 80);
alter table public.profiles add column if not exists state text check (state is null or char_length(state) <= 40);
alter table public.profiles add column if not exists certifications text check (certifications is null or char_length(certifications) <= 400);
alter table public.profiles add column if not exists accomplishments text check (accomplishments is null or char_length(accomplishments) <= 600);
alter table public.profiles add column if not exists availability text check (availability is null or availability in ('available','limited','unavailable'));

-- ---------------------------------------------------------------------------
-- 11. Row-level security
-- ---------------------------------------------------------------------------
alter table public.organizations enable row level security;
alter table public.organization_sports enable row level security;
alter table public.organization_expertise enable row level security;
alter table public.organization_needs enable row level security;
alter table public.organization_members enable row level security;
alter table public.organization_invites enable row level security;
alter table public.organization_verification_requests enable row level security;
alter table public.consult_invitations enable row level security;
alter table public.organization_inquiries enable row level security;
alter table public.analytics_events enable row level security;

-- organizations: members read; manage_org edits; owner deletes; no direct insert.
drop policy if exists "Members can view their organizations" on public.organizations;
create policy "Members can view their organizations" on public.organizations
  for select using (public.org_is_member(id));
drop policy if exists "Managers can update their organization" on public.organizations;
create policy "Managers can update their organization" on public.organizations
  for update using (public.org_has_perm(id, 'manage_org')) with check (public.org_has_perm(id, 'manage_org'));
drop policy if exists "Owners can delete their organization" on public.organizations;
create policy "Owners can delete their organization" on public.organizations
  for delete using (public.org_is_owner(id));

-- sports / expertise / needs: members read, managers write.
do $$
declare t text;
begin
  foreach t in array array['organization_sports','organization_expertise','organization_needs'] loop
    execute format('drop policy if exists "Members can view %1$s" on public.%1$s', t);
    execute format('create policy "Members can view %1$s" on public.%1$s for select using (public.org_is_member(organization_id))', t);
    execute format('drop policy if exists "Managers can insert %1$s" on public.%1$s', t);
    execute format('create policy "Managers can insert %1$s" on public.%1$s for insert with check (public.org_has_perm(organization_id, ''manage_org''))', t);
    execute format('drop policy if exists "Managers can update %1$s" on public.%1$s', t);
    execute format('create policy "Managers can update %1$s" on public.%1$s for update using (public.org_has_perm(organization_id, ''manage_org'')) with check (public.org_has_perm(organization_id, ''manage_org''))', t);
    execute format('drop policy if exists "Managers can delete %1$s" on public.%1$s', t);
    execute format('create policy "Managers can delete %1$s" on public.%1$s for delete using (public.org_has_perm(organization_id, ''manage_org''))', t);
  end loop;
end $$;

-- members: teammates read; manage_members edits/removes; anyone may leave.
drop policy if exists "Members can view teammates" on public.organization_members;
create policy "Members can view teammates" on public.organization_members
  for select using (public.org_is_member(organization_id));
drop policy if exists "Managers can update members" on public.organization_members;
create policy "Managers can update members" on public.organization_members
  for update using (public.org_has_perm(organization_id, 'manage_members'))
  with check (public.org_has_perm(organization_id, 'manage_members'));
drop policy if exists "Managers can remove members or members can leave" on public.organization_members;
create policy "Managers can remove members or members can leave" on public.organization_members
  for delete using (public.org_has_perm(organization_id, 'manage_members') or user_id = auth.uid());

-- invites: managers manage; the invited address can see its own invite.
drop policy if exists "Managers and invitees can view invites" on public.organization_invites;
create policy "Managers and invitees can view invites" on public.organization_invites
  for select using (
    public.org_has_perm(organization_id, 'manage_members')
    or lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
drop policy if exists "Managers can create invites" on public.organization_invites;
create policy "Managers can create invites" on public.organization_invites
  for insert with check (public.org_has_perm(organization_id, 'manage_members') and invited_by = auth.uid());
drop policy if exists "Managers can update invites" on public.organization_invites;
create policy "Managers can update invites" on public.organization_invites
  for update using (public.org_has_perm(organization_id, 'manage_members'))
  with check (public.org_has_perm(organization_id, 'manage_members'));
drop policy if exists "Managers can delete invites" on public.organization_invites;
create policy "Managers can delete invites" on public.organization_invites
  for delete using (public.org_has_perm(organization_id, 'manage_members'));

-- verification requests: managers submit and read; review is service-role only.
drop policy if exists "Managers can view verification requests" on public.organization_verification_requests;
create policy "Managers can view verification requests" on public.organization_verification_requests
  for select using (public.org_has_perm(organization_id, 'manage_org'));
drop policy if exists "Managers can submit verification requests" on public.organization_verification_requests;
create policy "Managers can submit verification requests" on public.organization_verification_requests
  for insert with check (
    public.org_has_perm(organization_id, 'manage_org')
    and requested_by = auth.uid() and status = 'pending'
  );

-- consult invitations: org contacts coaches; the coach reads and responds.
drop policy if exists "Org members and the coach can view invitations" on public.consult_invitations;
create policy "Org members and the coach can view invitations" on public.consult_invitations
  for select using (coach_id = auth.uid() or public.org_is_member(organization_id));
drop policy if exists "Org contacts can invite coaches" on public.consult_invitations;
create policy "Org contacts can invite coaches" on public.consult_invitations
  for insert with check (
    public.org_has_perm(organization_id, 'contact_coaches')
    and invited_by = auth.uid() and status = 'pending'
    and exists (select 1 from public.profiles p where p.id = coach_id and p.role = 'Coach')
  );
drop policy if exists "Coaches can respond to their invitations" on public.consult_invitations;
create policy "Coaches can respond to their invitations" on public.consult_invitations
  for update using (coach_id = auth.uid()) with check (coach_id = auth.uid());
drop policy if exists "Org contacts can withdraw invitations" on public.consult_invitations;
create policy "Org contacts can withdraw invitations" on public.consult_invitations
  for delete using (public.org_has_perm(organization_id, 'contact_coaches'));

-- inquiries: signed-in coaches write; the organization's team reads.
drop policy if exists "Org members and the sender can view inquiries" on public.organization_inquiries;
create policy "Org members and the sender can view inquiries" on public.organization_inquiries
  for select using (from_user_id = auth.uid() or public.org_is_member(organization_id));
drop policy if exists "Coaches can contact organizations" on public.organization_inquiries;
create policy "Coaches can contact organizations" on public.organization_inquiries
  for insert with check (
    from_user_id = auth.uid()
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'Coach')
  );

-- analytics: append-only for the person the event is about.
drop policy if exists "Anyone can record an analytics event" on public.analytics_events;
create policy "Anyone can record an analytics event" on public.analytics_events
  for insert to anon, authenticated with check (
    (user_id is null or user_id = auth.uid())
    and (organization_id is null or public.org_is_member(organization_id))
  );

-- opportunities: org-aware replacements for the original owner-only policies.
drop policy if exists "Clients can post their own opportunities" on public.opportunities;
create policy "Clients can post their own opportunities" on public.opportunities
  for insert with check (
    client_id = auth.uid()
    and (organization_id is null or public.org_has_perm(organization_id, 'post_opportunities'))
  );
drop policy if exists "Clients can update their own opportunities" on public.opportunities;
create policy "Clients can update their own opportunities" on public.opportunities
  for update
  using (client_id = auth.uid()
         or (organization_id is not null and public.org_has_perm(organization_id, 'post_opportunities')))
  with check (client_id = auth.uid()
         or (organization_id is not null and public.org_has_perm(organization_id, 'post_opportunities')));
drop policy if exists "Clients can delete their own opportunities" on public.opportunities;
create policy "Clients can delete their own opportunities" on public.opportunities
  for delete using (client_id = auth.uid()
         or (organization_id is not null and public.org_has_perm(organization_id, 'post_opportunities')));
drop policy if exists "Org members can view organization opportunities" on public.opportunities;
create policy "Org members can view organization opportunities" on public.opportunities
  for select using (organization_id is not null and public.org_is_member(organization_id));

-- ---------------------------------------------------------------------------
-- 12. Public profile view (public fields only)
-- ---------------------------------------------------------------------------
create or replace view public.organizations_public as
select
  o.id, o.organization_name, o.organization_type, o.description, o.website,
  o.logo_url, o.city, o.state, o.country, o.employee_count, o.athlete_count,
  o.preferred_format, o.verification_status, o.created_at,
  array(select coalesce(os.custom_name, s.name)
        from public.organization_sports os join public.sports s on s.id = os.sport_id
        where os.organization_id = o.id order by s.sort_order) as sports,
  array(select distinct e.name
        from public.organization_expertise oe join public.expertise e on e.id = oe.expertise_id
        where oe.organization_id = o.id) as expertise,
  array(select n.need_type from public.organization_needs n
        where n.organization_id = o.id order by n.need_type) as needs,
  (select count(*) from public.opportunities op
     where op.organization_id = o.id and op.status = 'open') as open_opportunities
from public.organizations o;

grant select on public.organizations_public to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 13. Functions the pages call
-- ---------------------------------------------------------------------------
-- Friendly pre-check used by the sign-up form before anything is created.
create or replace function public.organization_name_available(
  p_name text, p_city text, p_state text, p_website text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare dom text := public.normalize_domain(p_website);
begin
  if dom is not null and exists (select 1 from public.organizations where normalized_domain = dom) then
    return jsonb_build_object('available', false, 'field', 'website',
      'reason', 'An organization with this website is already on Remedy Coaching. Ask its owner to invite you to the team instead of creating a duplicate.');
  end if;
  if exists (select 1 from public.organizations
             where lower(organization_name) = lower(trim(p_name))
               and lower(coalesce(city,'')) = lower(trim(coalesce(p_city,'')))
               and lower(coalesce(state,'')) = lower(trim(coalesce(p_state,'')))) then
    return jsonb_build_object('available', false, 'field', 'organization_name',
      'reason', 'An organization with this name already exists in that city. Ask its owner to invite you to the team.');
  end if;
  return jsonb_build_object('available', true);
end;
$$;

grant execute on function public.organization_name_available(text, text, text, text) to anon, authenticated;

-- Creates the organization, its owner membership, sports, expertise and needs
-- in one transaction. Also makes sure the user has a (Client) profile so the
-- existing dashboard, applications and messaging keep working for them.
create or replace function public.create_organization(payload jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  org_id uuid;
  first_sport text;
  m jsonb := coalesce(payload -> 'member', '{}'::jsonb);
  display text;
  item jsonb;
begin
  if uid is null then raise exception 'AUTH_REQUIRED: sign in first'; end if;
  if not exists (select 1 from auth.users u where u.id = uid and u.email_confirmed_at is not null) then
    raise exception 'EMAIL_NOT_VERIFIED: verify your email first';
  end if;
  if coalesce(trim(payload ->> 'organization_name'), '') = '' then
    raise exception 'INVALID_INPUT: organization name is required';
  end if;

  begin
    insert into public.organizations (
      owner_id, organization_name, organization_type, description, website, email, phone,
      address, city, state, zip, country, employee_count, athlete_count, preferred_format,
      budget_min_cents, budget_max_cents)
    values (
      uid, trim(payload ->> 'organization_name'), payload ->> 'organization_type',
      nullif(trim(payload ->> 'description'), ''), nullif(trim(payload ->> 'website'), ''),
      nullif(trim(payload ->> 'email'), ''), nullif(trim(payload ->> 'phone'), ''),
      nullif(trim(payload ->> 'address'), ''), nullif(trim(payload ->> 'city'), ''),
      nullif(trim(payload ->> 'state'), ''), nullif(trim(payload ->> 'zip'), ''),
      coalesce(nullif(trim(payload ->> 'country'), ''), 'United States'),
      nullif(payload ->> 'employee_count', ''), nullif(payload ->> 'athlete_count', ''),
      nullif(payload ->> 'preferred_format', ''),
      nullif(payload ->> 'budget_min_cents', '')::integer, nullif(payload ->> 'budget_max_cents', '')::integer)
    returning id into org_id;
  exception when unique_violation then
    raise exception 'DUPLICATE_ORGANIZATION: an organization with this name or website already exists';
  end;

  display := nullif(trim(coalesce(m ->> 'first_name','') || ' ' || coalesce(m ->> 'last_name','')), '');
  insert into public.organization_members (organization_id, user_id, role, display_name, job_title)
  values (org_id, uid, 'owner', display, nullif(trim(m ->> 'job_title'), ''));

  for item in select * from jsonb_array_elements(coalesce(payload -> 'sports', '[]'::jsonb)) loop
    insert into public.organization_sports (organization_id, sport_id, custom_name)
    select org_id, s.id, nullif(trim(item ->> 'custom'), '')
    from public.sports s where s.name = item ->> 'name'
    on conflict do nothing;
    if first_sport is null then first_sport := coalesce(nullif(trim(item ->> 'custom'), ''), item ->> 'name'); end if;
  end loop;

  for item in select * from jsonb_array_elements(coalesce(payload -> 'expertise', '[]'::jsonb)) loop
    insert into public.organization_expertise (organization_id, expertise_id)
    select org_id, e.id from public.expertise e join public.sports s on s.id = e.sport_id
    where s.name = item ->> 'sport' and e.name = item ->> 'name'
    on conflict do nothing;
  end loop;

  for item in select * from jsonb_array_elements(coalesce(payload -> 'needs', '[]'::jsonb)) loop
    insert into public.organization_needs (organization_id, need_type, custom_text)
    values (org_id, item ->> 'type', nullif(trim(item ->> 'custom'), ''))
    on conflict do nothing;
  end loop;

  insert into public.profiles (id, email, name, role, sport)
  select uid, u.email, trim(payload ->> 'organization_name'), 'Client', coalesce(first_sport, 'Other')
  from auth.users u where u.id = uid
  on conflict (id) do nothing;

  return org_id;
end;
$$;

revoke all on function public.create_organization(jsonb) from public, anon;
grant execute on function public.create_organization(jsonb) to authenticated;

-- An invited person accepts from their own signed-in account; the invite must
-- be addressed to the email on that account.
create or replace function public.accept_org_invite(invite uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  inv public.organization_invites%rowtype;
  uid uuid := auth.uid();
  mail text := lower(coalesce(auth.jwt() ->> 'email', ''));
  display text;
begin
  if uid is null then raise exception 'AUTH_REQUIRED: sign in first'; end if;
  select * into inv from public.organization_invites where id = invite and status = 'pending';
  if not found or lower(inv.email) <> mail then
    raise exception 'INVITE_NOT_FOUND: this invitation is not available for your account';
  end if;
  select nullif(trim(coalesce(u.raw_user_meta_data ->> 'first_name','') || ' ' || coalesce(u.raw_user_meta_data ->> 'last_name','')), '')
    into display from auth.users u where u.id = uid;
  insert into public.organization_members (organization_id, user_id, role, display_name)
  values (inv.organization_id, uid, inv.role, display)
  on conflict (organization_id, user_id) do nothing;
  update public.organization_invites set status = 'accepted', accepted_at = now() where id = inv.id;
  return inv.organization_id;
end;
$$;

revoke all on function public.accept_org_invite(uuid) from public, anon;
grant execute on function public.accept_org_invite(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 14. Storage: public logos, private verification documents
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('org-logos', 'org-logos', true, 2097152, array['image/png','image/jpeg','image/webp'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('org-verification', 'org-verification', false, 10485760, array['application/pdf','image/png','image/jpeg'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Files live under "<organization id>/..."; this answers whether the current
-- user may manage that organization.
create or replace function public.org_path_can_manage(object_name text)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when split_part(object_name, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then public.org_has_perm(split_part(object_name, '/', 1)::uuid, 'manage_org')
    else false end;
$$;

drop policy if exists "Org managers upload logos" on storage.objects;
create policy "Org managers upload logos" on storage.objects
  for insert with check (bucket_id = 'org-logos' and public.org_path_can_manage(name));
drop policy if exists "Org managers replace logos" on storage.objects;
create policy "Org managers replace logos" on storage.objects
  for update using (bucket_id = 'org-logos' and public.org_path_can_manage(name));
drop policy if exists "Org managers delete logos" on storage.objects;
create policy "Org managers delete logos" on storage.objects
  for delete using (bucket_id = 'org-logos' and public.org_path_can_manage(name));

drop policy if exists "Org managers upload verification documents" on storage.objects;
create policy "Org managers upload verification documents" on storage.objects
  for insert with check (bucket_id = 'org-verification' and public.org_path_can_manage(name));
drop policy if exists "Org managers read verification documents" on storage.objects;
create policy "Org managers read verification documents" on storage.objects
  for select using (bucket_id = 'org-verification' and public.org_path_can_manage(name));
drop policy if exists "Org managers delete verification documents" on storage.objects;
create policy "Org managers delete verification documents" on storage.objects
  for delete using (bucket_id = 'org-verification' and public.org_path_can_manage(name));

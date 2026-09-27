-- Remedy Coaching — coach verification (public profiles + credential uploads)
-- Run this once in your Supabase project's SQL Editor, AFTER supabase-setup.sql
-- (and supabase-setup-additions.sql, if you've run that too). It only adds
-- new columns/tables — it does not touch existing data.

-- ---------------------------------------------------------------------------
-- 1. Verification fields on profiles
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists verified boolean not null default false;

alter table public.profiles
  add column if not exists verification_status text not null default 'unverified'
  check (verification_status in ('unverified', 'pending', 'verified', 'rejected'));

-- IMPORTANT: profiles already has a policy letting users update their own row
-- ("Users can update their own profile"). Without the guard below, a coach
-- could set their own `verified = true` directly through the API (e.g. from
-- the browser console), completely defeating the point of verification.
-- This trigger silently keeps verified/verification_status pinned to their
-- existing value whenever an ordinary logged-in user (role "authenticated")
-- is the one making the change — only a request made with the service role
-- key, or an edit from the Supabase Studio table editor, can move them.
create or replace function public.protect_verification_fields()
returns trigger
language plpgsql
security definer
as $$
begin
  if auth.role() = 'authenticated' then
    new.verified := old.verified;
    new.verification_status := old.verification_status;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_verification_fields on public.profiles;
create trigger protect_verification_fields
  before update on public.profiles
  for each row execute function public.protect_verification_fields();

-- ---------------------------------------------------------------------------
-- 2. Credentials — one row per uploaded certification / document
-- ---------------------------------------------------------------------------

create table public.credentials (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid references auth.users(id) on delete cascade not null,
  title text not null,               -- e.g. "USA Wrestling Level 3 Certification"
  issuer text,                       -- e.g. "USA Wrestling"
  file_path text not null,           -- path inside the 'credentials' storage bucket
  file_name text,                    -- original filename, for display
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewer_note text,
  created_at timestamptz default now(),
  reviewed_at timestamptz
);

alter table public.credentials enable row level security;

-- A coach can see their own credential rows, at any status.
create policy "Coaches can view their own credentials"
  on public.credentials for select
  using (auth.uid() = coach_id);

-- Anyone (including signed-out visitors) can see an APPROVED credential —
-- this is what powers the "Credentials" list on a public profile page.
-- Combined with the policy above via OR, so a coach still sees their own
-- pending/rejected rows too.
create policy "Approved credentials are publicly readable"
  on public.credentials for select
  using (status = 'approved');

-- A coach can only submit a credential as themselves, and it must start
-- out 'pending' — the status value itself is part of the check, so a
-- client can't insert a row that's already 'approved'.
create policy "Coaches can submit their own credentials"
  on public.credentials for insert
  with check (auth.uid() = coach_id and status = 'pending');

-- A coach can withdraw a credential while it's still awaiting review.
-- (No update policy is defined on purpose — moving a credential to
-- approved/rejected is a reviewer action, done from the Supabase Studio
-- table editor for now, the same way application status is handled in
-- supabase-setup-additions.sql.)
create policy "Coaches can withdraw their own pending credentials"
  on public.credentials for delete
  using (auth.uid() = coach_id and status = 'pending');

-- ---------------------------------------------------------------------------
-- 3. Storage bucket for the uploaded files themselves
-- ---------------------------------------------------------------------------
-- Private bucket — files are NOT publicly downloadable. Only the uploading
-- coach can read/write their own files; a reviewer opens them from the
-- Supabase Studio Storage browser (which uses an admin connection and
-- bypasses these policies) to check them before approving.

insert into storage.buckets (id, name, public)
values ('credentials', 'credentials', false)
on conflict (id) do nothing;

-- Files must be uploaded to a path like "<coach's auth uid>/<filename>" —
-- dashboard.html already does this — which is what lets these policies use
-- the first path segment as an ownership check.
create policy "Coaches can upload their own credential files"
  on storage.objects for insert
  with check (bucket_id = 'credentials' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "Coaches can view their own credential files"
  on storage.objects for select
  using (bucket_id = 'credentials' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "Coaches can delete their own credential files"
  on storage.objects for delete
  using (bucket_id = 'credentials' and auth.uid()::text = (storage.foldername(name))[1]);

-- ---------------------------------------------------------------------------
-- How to review and approve a credential (manual, for now):
--   1. Supabase dashboard -> Table Editor -> credentials
--   2. Open the file at its file_path via Storage -> credentials bucket
--   3. Set status to 'approved' or 'rejected' (and reviewer_note if useful)
--   4. Once a coach has at least one approved credential, set their row in
--      profiles: verification_status = 'verified', verified = true.
--      (Requires editing from Table Editor / SQL Editor — the trigger above
--      blocks this from the coach's own logged-in session, by design.)
-- ---------------------------------------------------------------------------

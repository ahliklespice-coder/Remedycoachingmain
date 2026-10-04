-- Remedy Coaching — "Coaching Strengths & Expertise" visual.
-- Run once in Supabase SQL Editor, after supabase-setup-match-quiz.sql (this
-- builds on the `specialties` column it adds).
--
-- Adds one field: a coach's own 1-5 rating for each specialty they've
-- selected, so the strength bars shown on their public profile, directory
-- card, and dashboard aren't all identical-length placeholders. This is a
-- self-reported field, same reasoning as `bio` / `specialties` themselves
-- in supabase-setup-match-quiz.sql: there's nothing here a coach shouldn't
-- be trusted to self-report, so it's covered by the existing "Users can
-- update their own profile" policy from supabase-setup.sql — no new RLS
-- policy or protect_verification_fields()-style trigger needed.

alter table public.profiles
  add column if not exists specialty_ratings jsonb not null default '{}'::jsonb;
  -- Shape: { "<specialty name from the specialties column>": 1-5, ... }
  -- e.g. { "Mental Performance": 5, "Recruiting Guidance": 3 }
  -- Keys are expected to match entries in `specialties`, but that's
  -- enforced client-side (dashboard.html only ever writes a rating for a
  -- specialty the coach has checked) rather than with a foreign-key-style
  -- constraint, since Postgres can't easily constrain jsonb keys against
  -- another column's array values. A stray/stale key just never renders
  -- (the strength-bars code only reads ratings for specialties currently
  -- in the `specialties` array), so this can't produce a bad UI state.

alter table public.profiles
  drop constraint if exists profiles_specialty_ratings_is_object;
alter table public.profiles
  add constraint profiles_specialty_ratings_is_object
  check (jsonb_typeof(specialty_ratings) = 'object');

-- Existing coaches (or ones who added specialties before this migration
-- ran) will have specialties with no rating yet. dashboard.html defaults
-- an unrated specialty's slider to 3 ("Strong") the first time they open
-- the edit form, and profile.html / coaches.html both fall back to the
-- same default of 3 when rendering strength bars for a specialty with no
-- recorded rating — so bars never render as empty/zero, and nothing here
-- claims more precision than "the coach rated this, or hasn't yet."

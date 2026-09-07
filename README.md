# Remedy Coaching

Static marketing site + community page for Remedy Coaching, deployed via Vercel to remedycoachinggroup.com.

## Structure

- `index.html` — homepage
- `community.html` — profile creation + posts feed, backed by Supabase (auth, database, realtime)
- `favicon.png`, `og-image.png` — referenced by meta tags in `index.html` and `community.html`
- `supabase-setup.sql` — run once in the Supabase SQL Editor to create the `profiles` and `posts` tables and their row-level security policies
- `assets/` — logo source files (SVG) and exported PNGs

## Setup

1. Deploy this repo to Vercel (Framework Preset: **Other**, no build step needed).
2. Point `remedycoachinggroup.com` at the Vercel project (Settings → Domains) and update DNS at your registrar to match.
3. Create a Supabase project, run `supabase-setup.sql` in its SQL Editor.
4. In `community.html`, set `SUPABASE_URL` and `SUPABASE_ANON_KEY` near the bottom of the `<script>` block (Supabase dashboard → Settings → API).
5. Commit and push — Vercel redeploys automatically on push to the production branch.

## Notes

- `community.html` requires both Supabase values above to be filled in, or it shows a setup warning banner and disables sign-in/posting.
- Auth uses email magic links (passwordless) via Supabase Auth.

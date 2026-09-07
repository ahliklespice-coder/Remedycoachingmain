-- Remedy Coaching — Supabase setup
-- Run this once in your Supabase project's SQL Editor (Dashboard -> SQL Editor -> New Query -> Run)

create extension if not exists "pgcrypto";

-- One row per user, linked to Supabase's built-in auth.users table
create table public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  email text,
  name text not null,
  role text not null,
  sport text not null,
  bio text,
  created_at timestamptz default now()
);

-- One row per post
create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid references auth.users(id) on delete cascade not null,
  author_name text not null,
  role text,
  sport text,
  content text not null,
  created_at timestamptz default now()
);

-- Row Level Security: locks down who can read/write what.
-- Without this, anyone with your public API key could write directly
-- to the database bypassing the app entirely.
alter table public.profiles enable row level security;
alter table public.posts enable row level security;

-- Anyone (including signed-out visitors) can read all profiles and posts
create policy "Profiles are publicly readable"
  on public.profiles for select
  using (true);

create policy "Posts are publicly readable"
  on public.posts for select
  using (true);

-- Users can only create/edit/delete their OWN profile
create policy "Users can insert their own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "Users can update their own profile"
  on public.profiles for update
  using (auth.uid() = id);

create policy "Users can delete their own profile"
  on public.profiles for delete
  using (auth.uid() = id);

-- Users can only create/delete their OWN posts
create policy "Users can insert their own posts"
  on public.posts for insert
  with check (auth.uid() = author_id);

create policy "Users can delete their own posts"
  on public.posts for delete
  using (auth.uid() = author_id);

-- Enable realtime so new/deleted posts show up live for every visitor
alter publication supabase_realtime add table public.posts;

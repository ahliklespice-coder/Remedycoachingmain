-- Remedy Coaching — subscription billing state, kept in sync by the Stripe
-- webhook handler (api/stripe-webhook.js). Never written to directly by the
-- browser client — only the server-side webhook (using the service role
-- key) and the checkout-session endpoint write here.

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null unique,
  plan text not null default 'free' check (plan in ('free','professional','elite')),
  status text not null default 'active' check (status in ('active','past_due','canceled')),
  stripe_customer_id text,
  stripe_subscription_id text,
  current_period_end timestamptz,
  updated_at timestamptz default now()
);

alter table public.subscriptions enable row level security;

-- Users can read their own billing status (used to show plan badges,
-- gate features, etc.) — never anyone else's.
create policy "Users can view their own subscription"
  on public.subscriptions for select
  using (auth.uid() = user_id);

-- No insert/update/delete policies for regular users on purpose: this table
-- is only ever written by server-side code using the service role key
-- (which bypasses RLS entirely), never by the browser client.

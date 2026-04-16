-- Create the standalone device_tokens table used by push notifications and
-- the delete-account Edge Function. The earlier migration 010 only added a
-- device_token column to profiles — this creates the proper table.

create table if not exists public.device_tokens (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users(id) on delete cascade,
  token       text        not null,
  platform    text        not null default 'apns',
  created_at  timestamptz not null default now()
);

alter table public.device_tokens enable row level security;

create policy "Users manage own tokens"
  on public.device_tokens
  for all
  using (auth.uid() = user_id);

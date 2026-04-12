-- =============================================================================
-- 003_profiles_add_email.sql
-- Add email column to profiles so the iOS User model can round-trip cleanly.
-- =============================================================================
alter table public.profiles
    add column if not exists email text not null default '';

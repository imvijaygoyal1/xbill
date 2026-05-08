-- NOTE: The email column was removed from the response in migration 025_medium_fixes.sql (M-33).
-- This migration is kept for history; the effective current definition is in 025.

-- Migration 018: lookup_profiles_by_email RPC
-- Allows authenticated users to check which email addresses belong to xBill profiles.
-- SECURITY DEFINER bypasses RLS so callers don't need SELECT on the profiles table.
-- Current user is excluded from results (no need to invite yourself).

CREATE OR REPLACE FUNCTION public.lookup_profiles_by_email(p_emails text[])
RETURNS TABLE(
    id          uuid,
    email       text,
    display_name text,
    avatar_url  text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p.id,
    p.email,
    p.display_name,
    p.avatar_url
  FROM profiles p
  WHERE p.email = ANY(p_emails)
    AND p.id != auth.uid();
$$;

-- Only authenticated users may call this function.
REVOKE EXECUTE ON FUNCTION public.lookup_profiles_by_email(text[]) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.lookup_profiles_by_email(text[]) TO authenticated;

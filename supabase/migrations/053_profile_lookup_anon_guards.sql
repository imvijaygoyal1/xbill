-- Migration 053: make the profile-lookup functions refuse anonymous callers ON PURPOSE.
--
-- Found by the SECURITY DEFINER sweep of 2026-08-31 (see AUDIT_REPORT.md → SECDEF-01), prompted by
-- PURGE-02, where `anon` could execute a SECURITY DEFINER function whose ownership guard was
-- skipped for NULL callers.
--
-- `search_profiles` and `lookup_profiles_by_email` are both SECURITY DEFINER — they bypass the RLS
-- on `profiles` by design — and both were executable by `anon`. Probed live with the public anon
-- key, both returned **HTTP 200 with 0 rows**, so nothing leaked.
--
-- But look at WHY nothing leaked:
--
--     WHERE p.id != auth.uid()          -- search_profiles
--     AND   p.id != auth.uid()          -- lookup_profiles_by_email
--
-- For an anonymous caller `auth.uid()` is NULL, so `p.id != NULL` evaluates to NULL — never true —
-- and every row is filtered out. **The protection is SQL three-valued logic, not intent.** Nothing
-- in either function says "this must not run unauthenticated", and nobody reading them would know
-- that the `!=` is load-bearing for security rather than just excluding yourself from your own
-- search results.
--
-- That is one refactor away from an unauthenticated enumeration oracle over every profile's
-- display name and avatar, and — via `lookup_profiles_by_email` — a way to confirm whether any
-- given email address belongs to an xBill user. Each of these ordinary-looking edits would do it:
--
--     WHERE p.id IS DISTINCT FROM auth.uid()
--     WHERE (auth.uid() IS NULL OR p.id != auth.uid())
--     WHERE p.id != COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
--
-- So the guard is made explicit and `anon` is revoked by name. Two independent layers: even if a
-- future edit breaks the NULL semantics, the RAISE stops it, and even if someone re-grants `anon`,
-- the RAISE still stops it.
--
-- `anon` must be named. Supabase's ALTER DEFAULT PRIVILEGES grants EXECUTE to `anon` explicitly on
-- every new function in `public`, and `REVOKE ... FROM PUBLIC` does not remove an explicit grant —
-- the same trap recorded for migrations 039, 042, 043 and 044.
--
-- Behaviour for a signed-in caller is UNCHANGED: same rows, same order, same limits. The only new
-- outcome is a clear error instead of a silent empty result for an unauthenticated one — which is
-- also better for debugging, since "0 rows" and "not allowed" are different answers.

-- search_profiles: 021 removed `email` from the return; 029 added the 2-character minimum.
-- Both are preserved verbatim below — CREATE OR REPLACE re-asserts the whole body, so every
-- guard in it is re-derived here deliberately, not inherited.
CREATE OR REPLACE FUNCTION public.search_profiles(p_query text)
RETURNS TABLE(id uuid, display_name text, avatar_url text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    -- NEW (053): the `p.id != auth.uid()` filter below already returns zero rows for an
    -- anonymous caller, but only as an accident of NULL comparison. Say it out loud.
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'You must be signed in to search profiles'
            USING ERRCODE = '42501';
    END IF;

    -- Reject queries shorter than 2 characters to prevent enumeration and
    -- to avoid expensive full-table ILIKE scans on single-character input.
    IF length(p_query) < 2 THEN
        RETURN;
    END IF;

    RETURN QUERY
        SELECT p.id, p.display_name, p.avatar_url
        FROM   profiles p
        WHERE  p.id != auth.uid()
          AND  (
                 p.email        ILIKE '%' || p_query || '%'
              OR p.display_name ILIKE '%' || p_query || '%'
               )
        LIMIT 20;
END;
$function$;

-- lookup_profiles_by_email: 025 removed `email` from the RETURNS TABLE. Preserved.
CREATE OR REPLACE FUNCTION public.lookup_profiles_by_email(p_emails text[])
RETURNS TABLE(id uuid, display_name text, avatar_url text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    -- NEW (053): same reasoning as search_profiles. This one is the more sensitive of the two —
    -- it answers "is this email address an xBill user?" — so an unauthenticated caller must be
    -- refused explicitly rather than by a NULL comparison nobody can see.
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'You must be signed in to look up contacts'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
        SELECT p.id, p.display_name, p.avatar_url
        FROM   profiles p
        WHERE  p.email = ANY(p_emails)
          AND  p.id != auth.uid();
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.search_profiles(text)            FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.search_profiles(text)            FROM anon;
GRANT  EXECUTE ON FUNCTION public.search_profiles(text)            TO authenticated;

REVOKE EXECUTE ON FUNCTION public.lookup_profiles_by_email(text[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.lookup_profiles_by_email(text[]) FROM anon;
GRANT  EXECUTE ON FUNCTION public.lookup_profiles_by_email(text[]) TO authenticated;

COMMENT ON FUNCTION public.search_profiles(text) IS
    'Profile search for signed-in users. SECURITY DEFINER: bypasses RLS on profiles, so anon must '
    'never hold EXECUTE and the auth.uid() IS NULL guard must stay. The p.id != auth.uid() filter '
    'is NOT the security boundary — it only excludes your own row.';

COMMENT ON FUNCTION public.lookup_profiles_by_email(text[]) IS
    'Contact discovery for signed-in users. SECURITY DEFINER: bypasses RLS on profiles and answers '
    '"is this email an xBill user?", so anon must never hold EXECUTE and the auth.uid() IS NULL '
    'guard must stay. Returns no email address (025).';

-- Migration 021: remove email column from search_profiles return type (M1)
-- Email is still used in the WHERE clause for searching, but is no longer
-- returned in results, preventing any authenticated user from enumerating
-- all registered email addresses via wildcard queries.

CREATE OR REPLACE FUNCTION public.search_profiles(p_query text)
RETURNS TABLE(
    id           uuid,
    display_name text,
    avatar_url   text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.display_name, p.avatar_url
  FROM   profiles p
  WHERE  p.id != auth.uid()
    AND  (
           p.email        ILIKE '%' || p_query || '%'
        OR p.display_name ILIKE '%' || p_query || '%'
         )
  LIMIT 20;
$$;

REVOKE EXECUTE ON FUNCTION public.search_profiles(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.search_profiles(text) TO authenticated;

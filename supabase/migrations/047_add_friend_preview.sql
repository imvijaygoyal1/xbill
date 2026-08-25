-- 047_add_friend_preview.sql
--
-- INV-09. Opening an add-friend link showed no one to add.
--
-- `MainTabView` resolves the user id from `xbill://add/<uuid>` (or `/add?user=<uuid>`) through
-- `FriendService.fetchProfiles(ids:)`, a direct select on `public.profiles`. That table's SELECT
-- policy allows reading only:
--
--     your own row, OR someone who shares an ACTIVE GROUP with you
--
-- **A new friend shares no group with you.** Creating that relationship is the entire purpose of
-- the link, so the lookup returned zero rows, nothing was preloaded, and the screen opened with
-- nobody on it. Verified against production: a signed-in user selecting another user's profile by
-- id gets `[]`.
--
-- This is the same shape as INV-01, where the group-invite preview read a table restricted to
-- existing members: **a capability check cannot be an RLS policy on the thing being granted.**
-- The fix is the same — a SECURITY DEFINER function keyed on the identifier the link carries.
-- Possession of the user id IS the capability; no policy is widened.

CREATE OR REPLACE FUNCTION public.get_add_friend_preview(p_user_id uuid)
RETURNS TABLE (
    id           uuid,
    display_name text,
    avatar_url   text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Consistent with 044/046: an unauthenticated caller has nothing to do with this.
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'You need to be signed in to add a friend'
            USING ERRCODE = '28000';
    END IF;

    -- Deliberately NOT email. The link's holder needs to recognise a person before sending a
    -- request; they do not need an address, and returning one would make any user id an email
    -- lookup. `search_profiles` had its email removed for exactly this reason (migration 021).
    RETURN QUERY
    SELECT p.id, p.display_name, p.avatar_url
      FROM public.profiles p
     WHERE p.id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_add_friend_preview(uuid) FROM PUBLIC;
-- Supabase grants EXECUTE to `anon` by default on every new function in `public`, and revoking
-- from PUBLIC does not remove an explicit grant. Named explicitly so the restriction is real.
REVOKE ALL ON FUNCTION public.get_add_friend_preview(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_add_friend_preview(uuid) TO authenticated;

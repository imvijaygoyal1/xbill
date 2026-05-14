-- 029_medium_rls_fixes.sql
-- Fixes for M-18, M-19, M-24, M-25 (DB-level), M-48

-- ─────────────────────────────────────────────────────────────────────────────
-- M-24: composite index on group_members(user_id, group_id)
--
-- The profiles SELECT policy in migration 023 uses a self-join on group_members
-- (gm1 JOIN gm2 ON gm1.group_id = gm2.group_id) which is O(N²) without an
-- index covering both columns.  This index also benefits is_group_member(),
-- create_group_with_member(), and the group_invites SELECT policy.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS group_members_user_group_idx
    ON public.group_members(user_id, group_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- M-18: group_members INSERT policy — prevent phantom user UUIDs
--
-- The existing policy (migration 006) allows:
--   (a) existing group members to add anyone (via is_group_member)
--   (b) the group creator to add themselves as the founding member
-- The atomic RPC create_group_with_member (migration 024) is SECURITY DEFINER
-- and bypasses RLS, so it is not affected by this change.
--
-- The fix adds an EXISTS check on profiles to both branches so that
-- arbitrary UUIDs that do not correspond to real accounts are rejected.
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "group_members: members can insert" ON public.group_members;

CREATE POLICY "group_members: members can insert"
    ON public.group_members FOR INSERT
    WITH CHECK (
        -- The inserted user_id must exist in profiles (real account)
        EXISTS (SELECT 1 FROM public.profiles WHERE id = user_id)
        AND (
            -- Branch A: existing member inviting someone to their group
            public.is_group_member(group_id)
            OR
            -- Branch B: group creator adding themselves as the founding member
            -- (before they appear in is_group_member for this new group)
            (
                auth.uid() = user_id
                AND EXISTS (
                    SELECT 1 FROM public.groups g
                    WHERE g.id          = group_id
                      AND g.created_by  = auth.uid()
                )
            )
        )
    );

-- ─────────────────────────────────────────────────────────────────────────────
-- M-19: search_profiles minimum query length of 2 characters
--
-- The previous version (migration 021) accepted any non-empty string,
-- allowing single-character queries that return large result sets and
-- enable user enumeration.  Adding a length guard early-exits for short
-- queries without changing the return type.
--
-- Must DROP + CREATE because CREATE OR REPLACE cannot change LANGUAGE from
-- sql to plpgsql.  The return type (id uuid, display_name text, avatar_url
-- text) is unchanged so no Swift client changes are required.
-- ─────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.search_profiles(text);

CREATE FUNCTION public.search_profiles(p_query text)
RETURNS TABLE(
    id           uuid,
    display_name text,
    avatar_url   text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
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
$$;

REVOKE EXECUTE ON FUNCTION public.search_profiles(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.search_profiles(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- M-48: send_friend_request TOCTOU race — replace IF EXISTS + INSERT with
--        INSERT … ON CONFLICT DO NOTHING using a partial unique index
--
-- The migration 025 bidirectional check (IF EXISTS … RETURN; INSERT) has a
-- TOCTOU window: two concurrent calls can both pass the SELECT and both
-- attempt the INSERT, with one winning and one failing with a constraint
-- error.  The canonical fix is a partial unique index on the canonical pair
-- (LEAST, GREATEST) so ON CONFLICT handles the race atomically.
--
-- The WHERE status != 'blocked' clause means blocked pairs are not covered
-- by the unique index and can be re-requested (intentional — blocking and
-- re-friending is a product-supported flow).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS friends_pair_unique
    ON public.friends(
        LEAST(requester_id, addressee_id),
        GREATEST(requester_id, addressee_id)
    )
    WHERE status != 'blocked';

CREATE OR REPLACE FUNCTION public.send_friend_request(p_addressee_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    p_requester_id uuid := auth.uid();
BEGIN
    -- INSERT … ON CONFLICT DO NOTHING is atomic: the partial unique index on
    -- (LEAST, GREATEST) prevents duplicate non-blocked pairs in a single
    -- statement, eliminating the TOCTOU window present in the old IF EXISTS
    -- approach.  Blocked pairs are not covered by the index, so a new request
    -- after blocking is allowed through (handled by application logic).
    INSERT INTO friends (requester_id, addressee_id, status)
    VALUES (p_requester_id, p_addressee_id, 'pending')
    ON CONFLICT DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.send_friend_request(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.send_friend_request(uuid) TO authenticated;

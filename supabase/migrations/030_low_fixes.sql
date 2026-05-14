-- 030_low_fixes.sql
-- Fixes for L-10 (splits settled_at consistency) and L-11 (join_group_via_invite unified error)

-- L-10: Add CHECK constraint to enforce settled_at / is_settled consistency.
-- A split where is_settled = false must not have a settled_at timestamp.
-- First, backfill rows that would violate the new constraint:
UPDATE public.splits
    SET settled_at = NULL
    WHERE is_settled = false AND settled_at IS NOT NULL;

ALTER TABLE public.splits
    ADD CONSTRAINT splits_settled_consistency
    CHECK (
        (is_settled = false AND settled_at IS NULL)
        OR (is_settled = true)
    );

-- L-11: Recreate join_group_via_invite to use a single unified error message for
-- both "token not found" and "token expired" cases, preventing user enumeration.
-- The implementation is otherwise identical to migration 027.
DROP FUNCTION IF EXISTS public.join_group_via_invite(text);
CREATE FUNCTION public.join_group_via_invite(p_token text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite public.group_invites%ROWTYPE;
BEGIN
    SELECT * INTO v_invite
    FROM public.group_invites
    WHERE token = p_token;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid or expired invite token';
    END IF;

    IF v_invite.expires_at < now() THEN
        RAISE EXCEPTION 'Invalid or expired invite token';
    END IF;

    -- Already a member? No-op (still return group_id so caller can navigate).
    IF NOT EXISTS (
        SELECT 1 FROM public.group_members
        WHERE group_id = v_invite.group_id AND user_id = auth.uid()
    ) THEN
        INSERT INTO public.group_members (group_id, user_id)
        VALUES (v_invite.group_id, auth.uid());
    END IF;

    -- Invalidate token after use (single-use tokens)
    DELETE FROM public.group_invites WHERE token = p_token;

    RETURN v_invite.group_id;
END;
$$;

REVOKE ALL ON FUNCTION public.join_group_via_invite(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.join_group_via_invite(text) TO authenticated;

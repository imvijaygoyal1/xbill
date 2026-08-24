-- 046_join_reactivates_member.sql
--
-- INV-07. Someone who had been **removed** from a group could never rejoin by invite. They saw the
-- correct group name, tapped Join, the sheet dismissed with no error — and no group appeared. The
-- same every time, because it is deterministic.
--
-- Migration 036 introduced historical membership: removing someone sets `is_active = false` and
-- keeps the row, so old expenses can still name them. `memberGroupIDs` reads only
-- `is_active = true`, so an inactive member sees none of the group.
--
-- `join_group_via_invite` guarded its insert with:
--
--     IF NOT EXISTS (SELECT 1 FROM group_members WHERE group_id = … AND user_id = …)
--
-- which does **not** consider `is_active`. A removed member's row still exists, so the insert was
-- skipped, the function returned the group id, and the client treated that as success. The join
-- reported success and did nothing.
--
-- 036 shipped `add_or_reactivate_group_member` for precisely this case, noting that "invite
-- acceptance reactivates existing inactive memberships instead of failing on conflict".
-- `join_group_via_invite` never used it, and two later rewrites of this function (042 and 044)
-- both preserved the bug.
--
-- The insert is now an UPSERT that reactivates, matching 036's semantics.

CREATE OR REPLACE FUNCTION public.join_group_via_invite(p_token text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite public.group_invites%ROWTYPE;
    v_user   uuid := auth.uid();
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'You need to be signed in to join a group'
            USING ERRCODE = '28000';
    END IF;

    SELECT * INTO v_invite FROM public.group_invites WHERE token = p_token;

    IF NOT FOUND OR v_invite.expires_at < now() THEN
        RAISE EXCEPTION 'Invalid or expired invite token';
    END IF;

    -- Reactivating, not merely inserting. `ON CONFLICT DO UPDATE` covers all three cases in one
    -- statement and cannot drift apart the way the old existence check did:
    --   * never a member          → insert, active
    --   * a member already        → no observable change, still active (idempotent: re-scanning
    --                               your own QR must not error)
    --   * a REMOVED member        → reactivated, which is the case that silently did nothing
    INSERT INTO public.group_members (group_id, user_id, is_active, removed_at)
    VALUES (v_invite.group_id, v_user, true, NULL)
    ON CONFLICT (group_id, user_id)
    DO UPDATE SET is_active  = true,
                  removed_at = NULL;

    -- No DELETE: the token stays usable until `expires_at` (INV-02). A QR is shown to a room.
    RETURN v_invite.group_id;
END;
$$;

REVOKE ALL ON FUNCTION public.join_group_via_invite(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.join_group_via_invite(text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.join_group_via_invite(text) TO authenticated;

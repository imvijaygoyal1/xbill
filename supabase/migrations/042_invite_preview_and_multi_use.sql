-- 042_invite_preview_and_multi_use.sql
--
-- Fixes two defects that made link/QR group invites unusable for the person being invited.
--
-- INV-01 — the invitee cannot read the invite.
--   `JoinGroupView` previews an invite by selecting `group_invites` and then `groups` directly.
--   Both are RLS-restricted to a group's creator or its existing members (027 CRIT-06 and 007),
--   and an invitee is neither — that is the entire point of an invite. Both selects return zero
--   rows, `.single()` raises PGRST116, and the screen renders "Invalid Invite. This invite link is
--   invalid or has expired." The join RPC itself is SECURITY DEFINER and would have worked, but
--   the preview fails first so the user never reaches it.
--
--   Fixed with `get_invite_preview`, a SECURITY DEFINER function returning only what the join
--   screen needs to show. Possession of the token is the capability; the policies are unchanged,
--   so nothing else about group visibility moves.
--
-- INV-02 — invite tokens were single-use, but a QR code is not.
--   027 (M-20) added `DELETE FROM group_invites` after a successful join. A QR code is shown to a
--   table of people or posted in a chat; the first person to scan it consumed it and everyone
--   after saw "expired". `expires_at` (7 days) is the intended lifetime and is now the only one.
--   This matches how shared invite links work elsewhere and is what the feature's own UI implies.

-- ---------------------------------------------------------------------------
-- INV-01: preview an invite without being able to read the group
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_invite_preview(p_token text)
RETURNS TABLE (
    group_id     uuid,
    name         text,
    emoji        text,
    currency     text,
    member_count integer,
    expires_at   timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite public.group_invites%ROWTYPE;
BEGIN
    SELECT * INTO v_invite FROM public.group_invites WHERE token = p_token;

    IF NOT FOUND OR v_invite.expires_at < now() THEN
        -- Deliberately identical for "no such token" and "expired": a caller must not be able to
        -- distinguish them, or the function becomes a token-existence oracle.
        RAISE EXCEPTION 'Invalid or expired invite token';
    END IF;

    RETURN QUERY
    SELECT g.id,
           g.name,
           g.emoji,
           g.currency,
           (SELECT count(*)::integer
              FROM public.group_members m
             WHERE m.group_id = g.id
               AND coalesce(m.is_active, true)),
           v_invite.expires_at
      FROM public.groups g
     WHERE g.id = v_invite.group_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_invite_preview(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_invite_preview(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- INV-02: an invite lives until it expires, not until first use
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.join_group_via_invite(p_token text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite public.group_invites%ROWTYPE;
BEGIN
    SELECT * INTO v_invite FROM public.group_invites WHERE token = p_token;

    IF NOT FOUND OR v_invite.expires_at < now() THEN
        RAISE EXCEPTION 'Invalid or expired invite token';
    END IF;

    -- Idempotent: re-scanning your own QR must not error, and must still navigate.
    IF NOT EXISTS (
        SELECT 1 FROM public.group_members
        WHERE group_id = v_invite.group_id AND user_id = auth.uid()
    ) THEN
        INSERT INTO public.group_members (group_id, user_id)
        VALUES (v_invite.group_id, auth.uid());
    END IF;

    -- NO DELETE. See INV-02 above: the token is reusable until `expires_at`.
    RETURN v_invite.group_id;
END;
$$;

REVOKE ALL ON FUNCTION public.join_group_via_invite(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.join_group_via_invite(text) TO authenticated;

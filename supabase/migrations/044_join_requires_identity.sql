-- 044_join_requires_identity.sql
--
-- INV-06. A caller with no valid session could open an invite, see the group's real name and
-- member count, tap Join — and get a raw Postgres constraint violation:
--
--   23502  null value in column "user_id" of relation "group_members"
--
-- because `join_group_via_invite` inserted `auth.uid()` without checking it. To the user that is
-- "the prompt named my group, I tapped Join, and nothing happened."
--
-- Two things made it reachable:
--   * `get_invite_preview` is executable by `anon` (Supabase grants EXECUTE to anon on every new
--     public function by default; `REVOKE … FROM PUBLIC` does not remove that explicit grant), so
--     the screen looks completely legitimate to a caller who cannot act on it.
--   * A session can expire while the app still holds a cached user, so this is reachable from a
--     signed-in-looking app, not only from a signed-out one.
--
-- The insert failing was correct. Failing as a NOT NULL violation was not: the caller cannot tell
-- an expired session from a broken app, and neither can the client code.

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
    -- Checked FIRST, before the token is even looked up: without an identity there is nothing this
    -- function can do, and reporting it plainly is the difference between "sign in again" and a
    -- constraint violation the user cannot act on.
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'You need to be signed in to join a group'
            USING ERRCODE = '28000';
    END IF;

    SELECT * INTO v_invite FROM public.group_invites WHERE token = p_token;

    IF NOT FOUND OR v_invite.expires_at < now() THEN
        RAISE EXCEPTION 'Invalid or expired invite token';
    END IF;

    -- Idempotent: re-scanning your own QR must not error, and must still navigate.
    IF NOT EXISTS (
        SELECT 1 FROM public.group_members
        WHERE group_id = v_invite.group_id AND user_id = v_user
    ) THEN
        INSERT INTO public.group_members (group_id, user_id)
        VALUES (v_invite.group_id, v_user);
    END IF;

    -- No DELETE: the token stays usable until `expires_at` (INV-02). A QR code is shown to a room.
    RETURN v_invite.group_id;
END;
$$;

REVOKE ALL ON FUNCTION public.join_group_via_invite(text) FROM PUBLIC;
-- Explicitly removes the default grant Supabase gives every new public function. `anon` cannot
-- usefully call this — it now fails immediately — but leaving the grant implies otherwise.
REVOKE ALL ON FUNCTION public.join_group_via_invite(text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.join_group_via_invite(text) TO authenticated;

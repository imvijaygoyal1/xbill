-- 027_crit_rls_fixes.sql
-- Fixes for CRIT-03/04/05/06/07, H-10, H-11, M-22

-- CRIT-03: groups UPDATE — only the creator may mutate group metadata
DROP POLICY IF EXISTS "groups: members can update" ON public.groups;
CREATE POLICY "groups: creator can update"
    ON public.groups FOR UPDATE
    USING  ( auth.uid() = created_by )
    WITH CHECK ( auth.uid() = created_by );

-- M-22: groups DELETE — only the creator may delete a group
DROP POLICY IF EXISTS "groups: creator can delete" ON public.groups;
CREATE POLICY "groups: creator can delete"
    ON public.groups FOR DELETE
    USING ( auth.uid() = created_by );

-- CRIT-04: ious UPDATE — parties can only flip is_settled; no field mutation
DROP POLICY IF EXISTS "parties can settle" ON public.ious;
CREATE POLICY "parties can settle"
    ON public.ious FOR UPDATE
    USING  ( auth.uid() = lender_id OR auth.uid() = borrower_id )
    WITH CHECK ( auth.uid() = lender_id OR auth.uid() = borrower_id );

-- CRIT-05: friends UPDATE — addressee may only accept or block
DROP POLICY IF EXISTS "addressee can update" ON public.friends;
CREATE POLICY "addressee can update"
    ON public.friends FOR UPDATE
    USING  ( auth.uid() = addressee_id )
    WITH CHECK (
        auth.uid() = addressee_id
        AND status IN ('accepted', 'blocked')
    );

-- CRIT-06: group_invites SELECT — restrict to creator or existing group member
DROP POLICY IF EXISTS "authenticated users can read invites" ON public.group_invites;
CREATE POLICY "creator or member can read invites"
    ON public.group_invites FOR SELECT
    USING (
        auth.uid() = created_by
        OR group_id IN (
            SELECT group_id FROM public.group_members WHERE user_id = auth.uid()
        )
    );

-- CRIT-07: device_tokens FOR ALL — add WITH CHECK so INSERT is also constrained
-- Drop existing policies first
DROP POLICY IF EXISTS "Users manage own tokens" ON public.device_tokens;
DROP POLICY IF EXISTS "Users update own tokens" ON public.device_tokens;
CREATE POLICY "Users manage own tokens"
    ON public.device_tokens
    FOR ALL
    USING     ( auth.uid() = user_id )
    WITH CHECK ( auth.uid() = user_id );

-- H-10: functional index on profiles.email for case-insensitive lookup
CREATE INDEX IF NOT EXISTS profiles_email_lower_idx
    ON public.profiles (lower(email));

-- H-11: drop the old 7-parameter overload of add_expense_with_splits
-- (migration 013 replaced it with an 11-param version but never dropped the old one)
DROP FUNCTION IF EXISTS public.add_expense_with_splits(
    uuid, uuid, numeric, text, text, text,
    public.split_input[]
);

-- M-20: invalidate (delete) invite token after successful use
-- Replace join_group_via_invite to delete the token on success
CREATE OR REPLACE FUNCTION public.join_group_via_invite(p_token text)
RETURNS void
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

    -- Already a member? No-op.
    IF EXISTS (
        SELECT 1 FROM public.group_members
        WHERE group_id = v_invite.group_id AND user_id = auth.uid()
    ) THEN
        RETURN;
    END IF;

    INSERT INTO public.group_members (group_id, user_id)
    VALUES (v_invite.group_id, auth.uid());

    -- Invalidate token after use
    DELETE FROM public.group_invites WHERE token = p_token;
END;
$$;

REVOKE ALL ON FUNCTION public.join_group_via_invite(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.join_group_via_invite(text) TO authenticated;

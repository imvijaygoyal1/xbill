-- 028_creator_remove_member.sql
-- Allow the group creator to remove any member from their group (M-21).
-- Without this, removeMember calls from the creator silently no-op because
-- the existing DELETE policy only allows users to remove themselves.

DROP POLICY IF EXISTS "creator can remove members" ON public.group_members;
CREATE POLICY "creator can remove members"
    ON public.group_members FOR DELETE
    USING (
        group_id IN (
            SELECT id FROM public.groups WHERE created_by = auth.uid()
        )
    );

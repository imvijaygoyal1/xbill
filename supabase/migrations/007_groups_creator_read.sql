-- =============================================================================
-- 007_groups_creator_read.sql
-- Fix: group creator can read their own group before being added as a member.
-- The groups SELECT policy previously required is_group_member(id), which
-- returns false for a brand-new group (member row doesn't exist yet when the
-- INSERT RETURNING clause executes). This caused a decoding failure in the app.
-- =============================================================================

DROP POLICY IF EXISTS "groups: members can read" ON public.groups;

CREATE POLICY "groups: members can read"
    ON public.groups FOR SELECT
    USING (
        public.is_group_member(id)
        OR auth.uid() = created_by
    );

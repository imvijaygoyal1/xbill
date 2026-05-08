-- 023_high_rls_fixes.sql
-- H-01: Add DELETE policy on splits
-- H-02: Add cross-group profile read policy
-- H-03: Add UPDATE policy on device_tokens

-- H-01: splits DELETE was missing; expense ON DELETE CASCADE works server-side
-- but any direct client-side delete path was blocked by RLS.
CREATE POLICY "Group members can delete splits"
    ON public.splits
    FOR DELETE
    USING (is_expense_group_member(expense_id));

-- H-02: profiles only allowed own-row SELECT. Group members couldn't read each
-- other's display names, breaking member-name display for all group views.
CREATE POLICY "Group members can read each other's profiles"
    ON public.profiles
    FOR SELECT
    USING (
        auth.uid() = id
        OR EXISTS (
            SELECT 1
            FROM public.group_members gm1
            JOIN public.group_members gm2
              ON gm1.group_id = gm2.group_id
            WHERE gm1.user_id = auth.uid()
              AND gm2.user_id = profiles.id
        )
    );

-- H-03: device_tokens FOR ALL does not cover UPDATE in Supabase/Postgres.
-- APNs token refresh upserts (ON CONFLICT DO UPDATE) were silently blocked.
CREATE POLICY "Users can update own device tokens"
    ON public.device_tokens
    FOR UPDATE
    USING  (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

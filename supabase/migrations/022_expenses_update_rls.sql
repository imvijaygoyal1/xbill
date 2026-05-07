-- 022_expenses_update_rls.sql
-- Adds an UPDATE RLS policy on the expenses table.
-- Without this, any call to UPDATE expenses (e.g. editing an expense or advancing
-- next_occurrence_date) silently fails for every user at the DB level.
-- The is_group_member() helper is defined in migration 001.

CREATE POLICY "Group members can update expenses"
    ON public.expenses
    FOR UPDATE
    USING  (is_group_member(group_id))
    WITH CHECK (is_group_member(group_id));

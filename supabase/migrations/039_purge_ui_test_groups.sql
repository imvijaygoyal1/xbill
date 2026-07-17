-- Migration 039: controlled cleanup for UI-test-created groups.
-- The function defaults to dry-run and only targets approved test prefixes for
-- a single owner. Deleting groups cascades to group_members, group_invites,
-- expenses, splits, and comments through existing foreign keys.

CREATE OR REPLACE FUNCTION public.purge_ui_test_groups(
    p_execute boolean DEFAULT false,
    p_prefixes text[] DEFAULT ARRAY[
        'Regression',
        'ExpenseForm',
        'ArchiveCycle',
        'ExpenseDetail',
        'ReceiptManual',
        'SplitModes',
        'GroupSettings',
        'SettleSurface',
        'UITest',
        'ArchiveTest'
    ]::text[],
    p_created_by uuid DEFAULT auth.uid()
)
RETURNS TABLE (
    group_id uuid,
    group_name text,
    was_archived boolean,
    deleted boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    caller_id uuid := auth.uid();
    effective_created_by uuid := COALESCE(p_created_by, caller_id);
    allowed_prefixes constant text[] := ARRAY[
        'Regression',
        'ExpenseForm',
        'ArchiveCycle',
        'ExpenseDetail',
        'ReceiptManual',
        'SplitModes',
        'GroupSettings',
        'SettleSurface',
        'UITest',
        'ArchiveTest'
    ]::text[];
    invalid_prefixes text[];
BEGIN
    IF effective_created_by IS NULL THEN
        RAISE EXCEPTION 'p_created_by is required when auth.uid() is unavailable';
    END IF;

    -- Authenticated clients may only purge their own test groups. Database
    -- maintenance jobs using a privileged connection can pass p_created_by.
    IF caller_id IS NOT NULL AND effective_created_by <> caller_id THEN
        RAISE EXCEPTION 'Cannot purge test groups for another user';
    END IF;

    IF COALESCE(array_length(p_prefixes, 1), 0) = 0 THEN
        RAISE EXCEPTION 'At least one prefix is required';
    END IF;

    SELECT array_agg(prefix)
      INTO invalid_prefixes
      FROM unnest(p_prefixes) AS prefix
     WHERE prefix <> ALL (allowed_prefixes);

    IF invalid_prefixes IS NOT NULL THEN
        RAISE EXCEPTION 'Unsupported test group prefix(es): %', invalid_prefixes;
    END IF;

    IF p_execute THEN
        RETURN QUERY
        WITH target_groups AS MATERIALIZED (
            SELECT g.id, g.name, g.is_archived
              FROM public.groups g
             WHERE g.created_by = effective_created_by
               AND EXISTS (
                   SELECT 1
                     FROM unnest(p_prefixes) AS prefix
                    WHERE g.name LIKE prefix || '-%'
               )
        ),
        deleted_groups AS (
            DELETE FROM public.groups g
             WHERE g.id IN (SELECT target_groups.id FROM target_groups)
             RETURNING g.id
        )
        SELECT tg.id, tg.name, tg.is_archived, true
          FROM target_groups tg
          JOIN deleted_groups dg ON dg.id = tg.id
         ORDER BY tg.name;
    ELSE
        RETURN QUERY
        SELECT g.id, g.name, g.is_archived, false
          FROM public.groups g
         WHERE g.created_by = effective_created_by
           AND EXISTS (
               SELECT 1
                 FROM unnest(p_prefixes) AS prefix
                WHERE g.name LIKE prefix || '-%'
           )
         ORDER BY g.name;
    END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.purge_ui_test_groups(boolean, text[], uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.purge_ui_test_groups(boolean, text[], uuid) TO authenticated;

-- Migration 052: purge_ui_test_groups — cover every prefix the UI suite creates,
-- and actually revoke `anon`.
--
-- Two problems, found on 2026-08-31 by checking production counts after a full
-- `RegressionUITests` run instead of trusting the script's own "cleanup verified" line.
--
-- 1. THREE prefixes the UI tests create were never in `allowed_prefixes`, so their groups
--    could not be purged — the function rejects them as "Unsupported test group prefix(es)",
--    which means the cleanup script cannot even be asked to remove them. They accumulated in
--    production for over a month:
--
--       PaymentReturn   37 groups, 37 expenses, 37 splits   since 2026-07-27
--       ScrollProbe     14 groups                            since 2026-08-24
--       Validation       0 groups (used by a test that cancels before creating one)
--
--    `Validation` is added anyway so it cannot start accumulating later.
--
--    The prefix list is enumerated from the test target, not guessed:
--        grep -rhoE 'uniqueName\(prefix: "[^"]+"\)' xBillUITests/*.swift
--    Re-run that after adding a UI test that creates a group, or its data is unpurgeable.
--
-- 2. **`anon` could execute this SECURITY DEFINER function.** The ownership guard is
--    `IF caller_id IS NOT NULL AND effective_created_by <> caller_id`, and `auth.uid()` is NULL
--    for an anonymous caller — so the guard is SKIPPED, not failed. An unauthenticated caller
--    holding the public anon key could pass `p_created_by => '<any user id>', p_execute => true`
--    and delete that user's groups matching an approved prefix, cascading to expenses, splits,
--    comments and members.
--
--    039's `REVOKE EXECUTE … FROM PUBLIC` reads as a lock and is not one: Supabase's
--    ALTER DEFAULT PRIVILEGES grants EXECUTE to `anon` explicitly at creation, and revoking from
--    PUBLIC does not remove an explicit grant. `anon` must be named. Same finding as migrations
--    042/043 and the 044 note.
--
--    The NULL-caller path is deliberately KEPT rather than hardened away: the maintenance script
--    `scripts/purge-ui-test-groups.sh` connects on a privileged connection where `auth.uid()` is
--    NULL and passes `p_created_by` explicitly. Requiring a non-NULL caller would break it. With
--    `anon` revoked, that path is reachable only by a privileged connection, which is the intent.
--
-- The whole body is re-emitted below because CREATE OR REPLACE re-asserts it. Every guard from
-- 039 is preserved verbatim; only the two prefix arrays change. The argument list is unchanged
-- (boolean, text[], uuid), so this replaces the function rather than creating an overload.

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
        'ArchiveTest',
        'PaymentReturn',
        'ScrollProbe',
        'Validation'
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
        'ArchiveTest',
        'PaymentReturn',
        'ScrollProbe',
        'Validation'
    ]::text[];
    invalid_prefixes text[];
BEGIN
    IF effective_created_by IS NULL THEN
        RAISE EXCEPTION 'p_created_by is required when auth.uid() is unavailable';
    END IF;

    -- Authenticated clients may only purge their own test groups. Database
    -- maintenance jobs using a privileged connection can pass p_created_by.
    -- NOTE: this is skipped when caller_id IS NULL, which is why `anon` must not hold
    -- EXECUTE on this function — see the header and the REVOKE below.
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

-- FROM PUBLIC is kept for parity with 039 but does nothing on its own here; the line that
-- matters is the one naming `anon`.
REVOKE EXECUTE ON FUNCTION public.purge_ui_test_groups(boolean, text[], uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.purge_ui_test_groups(boolean, text[], uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.purge_ui_test_groups(boolean, text[], uuid) TO authenticated;

COMMENT ON FUNCTION public.purge_ui_test_groups(boolean, text[], uuid) IS
    'Deletes UI-test groups for one owner, dry-run by default. anon must never hold EXECUTE: the '
    'ownership guard is skipped when auth.uid() is NULL, so an anonymous caller passing '
    'p_created_by could delete another user''s prefixed groups. Keep allowed_prefixes in sync with '
    'grep -rhoE ''uniqueName\(prefix: "[^"]+"\)'' xBillUITests/*.swift';

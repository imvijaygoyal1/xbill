-- 051_expense_concurrency.sql
--
-- Two people editing the same expense silently overwrite each other. Last write wins, no
-- conflict, no warning, and the thing being overwritten is money. Live since 043 added
-- `updated_at` on 2026-08-23 and nothing ever read it.
--
-- See docs/superpowers/specs/2026-08-29-expense-optimistic-concurrency-design.md

-- Who last changed the row, so the conflict message can name them. Nullable on purpose: rows
-- that predate this migration have no author and inventing one would be a lie. A null renders
-- as "Someone".
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS updated_by uuid;

-- Order is load-bearing. SET NOT NULL fails if the backfill has not run. `created_at` is a
-- truthful "last known change" for a row that has never been edited.
UPDATE public.expenses SET updated_at = created_at WHERE updated_at IS NULL;
ALTER TABLE public.expenses ALTER COLUMN updated_at SET DEFAULT now();
ALTER TABLE public.expenses ALTER COLUMN updated_at SET NOT NULL;

-- DROP + CREATE, never CREATE OR REPLACE.
--
-- CREATE OR REPLACE with a DIFFERENT argument list does not replace the function -- it creates a
-- second overload, and PostgREST is then left with two candidates. That is defect H-11 in this
-- repository: the old 7-parameter `add_expense_with_splits` was left executable after migration
-- 013 for exactly this reason.
DROP FUNCTION IF EXISTS public.update_expense_with_splits(
    uuid, text, numeric, text, text, text, uuid, public.split_input[]);

CREATE FUNCTION public.update_expense_with_splits(
    p_expense_id          uuid,
    p_title               text,
    p_amount              numeric,
    p_currency            text,
    p_category            text,
    p_notes               text                  DEFAULT NULL,
    p_paid_by             uuid                  DEFAULT NULL,
    p_splits              public.split_input[]  DEFAULT NULL,
    -- The compatibility hinge. Clients on 1.0-1.5 send 8 keys, resolve to this same function,
    -- receive NULL here, and skip the check -- they keep working untouched. They also remain
    -- able to clobber, which cannot be fixed without breaking them.
    p_expected_updated_at timestamptz           DEFAULT NULL
)
RETURNS public.expenses
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_expense public.expenses%ROWTYPE;
    v_sum     numeric;
BEGIN
    IF p_splits IS NULL OR array_length(p_splits, 1) IS NULL THEN
        RAISE EXCEPTION 'An expense must have at least one split';
    END IF;

    SELECT coalesce(sum(s.amount), 0) INTO v_sum FROM unnest(p_splits) AS s;
    IF round(v_sum, 2) <> round(p_amount, 2) THEN
        RAISE EXCEPTION 'Splits sum to % but the expense is %', v_sum, p_amount;
    END IF;

    UPDATE public.expenses
       SET title      = p_title,
           amount     = p_amount,
           currency   = p_currency,
           category   = p_category,
           notes      = p_notes,
           paid_by    = p_paid_by,
           updated_at = now(),
           updated_by = auth.uid()
     WHERE id = p_expense_id
       AND (p_expected_updated_at IS NULL OR updated_at = p_expected_updated_at)
    RETURNING * INTO v_expense;

    IF v_expense.id IS NULL THEN
        -- Distinguish "someone else changed it" from "gone, or RLS refused it". Without this
        -- branch a conflict is indistinguishable from a permission failure and the client cannot
        -- offer a reload. The EXISTS runs in the same transaction as the UPDATE, so the two
        -- cannot disagree.
        IF p_expected_updated_at IS NOT NULL
           AND EXISTS (SELECT 1 FROM public.expenses WHERE id = p_expense_id) THEN
            RAISE EXCEPTION 'This expense was changed by someone else'
                USING ERRCODE = 'XB409';
        END IF;
        RAISE EXCEPTION 'Expense not found, or you do not have permission to edit it';
    END IF;

    DELETE FROM public.splits WHERE expense_id = p_expense_id;

    INSERT INTO public.splits (expense_id, user_id, amount)
    SELECT p_expense_id, s.user_id, s.amount FROM unnest(p_splits) AS s;

    RETURN v_expense;
END;
$$;

-- Grants die with the dropped function and must be re-issued.
--
-- REVOKE ... FROM PUBLIC does NOT restrict anything on Supabase: ALTER DEFAULT PRIVILEGES grants
-- EXECUTE to `anon` explicitly at creation, and revoking from PUBLIC does not remove an explicit
-- grant. `anon` must be named. The REVOKE ... FROM PUBLIC lines in 042 and 043 read as protection
-- and are not.
REVOKE ALL ON FUNCTION public.update_expense_with_splits(
    uuid, text, numeric, text, text, text, uuid, public.split_input[], timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_expense_with_splits(
    uuid, text, numeric, text, text, text, uuid, public.split_input[], timestamptz) FROM anon;
GRANT  EXECUTE ON FUNCTION public.update_expense_with_splits(
    uuid, text, numeric, text, text, text, uuid, public.split_input[], timestamptz) TO authenticated;

COMMENT ON COLUMN public.expenses.updated_at IS
    'Optimistic-concurrency token. Clients send the value they loaded as p_expected_updated_at; '
    'update_expense_with_splits refuses the write if it no longer matches (SQLSTATE XB409).';
COMMENT ON COLUMN public.expenses.updated_by IS
    'Who last edited the row, so a conflict can name them. Nullable: rows predating migration 051 '
    'have no recorded author.';

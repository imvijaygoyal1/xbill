-- 043_update_expense_with_splits.sql
--
-- SPLIT-02. Editing an expense updated `expenses` and never touched `splits`, and balances derive
-- from splits — so correcting a 100 dinner to 120 displayed 120 while every balance still
-- reflected 100. The edit saved successfully and moved nothing.
--
-- The fix is a single transaction that updates the expense and replaces its splits, mirroring
-- `add_expense_with_splits`. Doing it as three client-side writes would leave a window where an
-- expense's splits do not sum to it, and a crash inside that window would persist the mismatch.
--
-- NOT `SECURITY DEFINER`: `splits` already carries group-member-scoped INSERT, DELETE and SELECT
-- policies, and `expenses` an UPDATE policy (022). RLS is therefore the authorisation, exactly as
-- for a direct write, and this function adds atomicity rather than privilege.

-- Records when an expense last changed. Nothing reads it yet; it exists so that optimistic
-- concurrency can be added without a second migration once editing is in real use. Two people
-- editing the same expense currently overwrite each other silently.
ALTER TABLE public.expenses
    ADD COLUMN IF NOT EXISTS updated_at timestamptz;

CREATE OR REPLACE FUNCTION public.update_expense_with_splits(
    p_expense_id uuid,
    p_title      text,
    p_amount     numeric,
    p_currency   text,
    p_category   text,
    p_notes      text,
    p_paid_by    uuid,
    p_splits     public.split_input[]
)
RETURNS public.expenses
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_expense public.expenses%ROWTYPE;
    v_sum     numeric;
BEGIN
    IF array_length(p_splits, 1) IS NULL THEN
        RAISE EXCEPTION 'An expense must have at least one split';
    END IF;

    -- The invariant this function exists to protect. Rejecting here makes "splits that do not sum
    -- to the expense" unrepresentable, rather than something a later balance calculation silently
    -- disagrees about.
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
           updated_at = now()
     WHERE id = p_expense_id
    RETURNING * INTO v_expense;

    -- Zero rows means the row is gone or RLS refused it. Without this the function would go on to
    -- delete and reinsert splits for an expense the caller may not own.
    IF v_expense.id IS NULL THEN
        RAISE EXCEPTION 'Expense not found, or you do not have permission to edit it';
    END IF;

    DELETE FROM public.splits WHERE expense_id = p_expense_id;

    INSERT INTO public.splits (expense_id, user_id, amount)
    SELECT p_expense_id, s.user_id, s.amount FROM unnest(p_splits) AS s;

    RETURN v_expense;
END;
$$;

REVOKE ALL ON FUNCTION public.update_expense_with_splits(uuid, text, numeric, text, text, text, uuid, public.split_input[]) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.update_expense_with_splits(uuid, text, numeric, text, text, text, uuid, public.split_input[]) TO authenticated;

-- 045_update_expense_defaults.sql
--
-- SPLIT-04. `update_expense_with_splits` was created with **no default arguments**, so PostgREST
-- required all 8 keys in the request body. Swift's synthesized `Encodable` omits a nil, so an
-- expense with no notes sent 7 keys and PostgREST answered:
--
--   PGRST202  Could not find the function public.update_expense_with_splits(p_amount, …)
--
-- which reached the user as a raw error the moment they tried to re-split an expense.
--
-- The client is fixed to always send explicit nulls, and that alone would be enough. Defaults are
-- added anyway because `add_expense_with_splits` has 8 of them and has never shown this failure —
-- one omitted key should not be able to make a function *disappear*. Depending solely on the
-- client to serialise perfectly is the arrangement that just failed.

CREATE OR REPLACE FUNCTION public.update_expense_with_splits(
    p_expense_id uuid,
    p_title      text,
    p_amount     numeric,
    p_currency   text,
    p_category   text,
    p_notes      text                  DEFAULT NULL,
    p_paid_by    uuid                  DEFAULT NULL,
    p_splits     public.split_input[]  DEFAULT NULL
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
           updated_at = now()
     WHERE id = p_expense_id
    RETURNING * INTO v_expense;

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
REVOKE ALL ON FUNCTION public.update_expense_with_splits(uuid, text, numeric, text, text, text, uuid, public.split_input[]) FROM anon;
GRANT  EXECUTE ON FUNCTION public.update_expense_with_splits(uuid, text, numeric, text, text, text, uuid, public.split_input[]) TO authenticated;

-- Recurring expenses (P4-B)
-- `recurrence` controls how often the expense repeats.
-- `next_occurrence_date` is when the next instance should be created (null once consumed).

ALTER TABLE public.expenses
    ADD COLUMN IF NOT EXISTS recurrence            text        NOT NULL DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS next_occurrence_date  timestamptz;

-- Drop old RPC signature (params changed) then recreate
DROP FUNCTION IF EXISTS public.add_expense_with_splits(
    uuid, uuid, numeric, text, text, text, text, text, split_input[], numeric, text
);

CREATE OR REPLACE FUNCTION public.add_expense_with_splits(
    p_group_id              uuid,
    p_paid_by               uuid,
    p_amount                numeric(10, 2),
    p_title                 text,
    p_category              text,
    p_currency              text          DEFAULT 'USD',
    p_notes                 text          DEFAULT null,
    p_receipt_url           text          DEFAULT null,
    p_splits                split_input[] DEFAULT array[]::split_input[],
    p_original_amount       numeric       DEFAULT null,
    p_original_currency     text          DEFAULT null,
    p_recurrence            text          DEFAULT 'none',
    p_next_occurrence_date  timestamptz   DEFAULT null
)
RETURNS public.expenses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_expense    public.expenses;
    v_splits_sum numeric(10, 2);
    v_split      public.split_input;
BEGIN
    IF auth.uid() <> p_paid_by THEN
        RAISE EXCEPTION 'paid_by must match the authenticated user'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT public.is_group_member(p_group_id) THEN
        RAISE EXCEPTION 'caller is not a member of group %', p_group_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT COALESCE(SUM(s.amount), 0)
    INTO   v_splits_sum
    FROM   unnest(p_splits) AS s;

    IF ROUND(v_splits_sum, 2) <> ROUND(p_amount, 2) THEN
        RAISE EXCEPTION 'split amounts (%) do not sum to expense total (%)',
            v_splits_sum, p_amount
            USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO public.expenses (
        group_id, paid_by, amount, title, category, currency, notes, receipt_url,
        original_amount, original_currency, recurrence, next_occurrence_date
    ) VALUES (
        p_group_id, p_paid_by, p_amount, p_title, p_category, p_currency, p_notes, p_receipt_url,
        p_original_amount, p_original_currency, p_recurrence, p_next_occurrence_date
    )
    RETURNING * INTO v_expense;

    FOREACH v_split IN ARRAY p_splits LOOP
        INSERT INTO public.splits (expense_id, user_id, amount)
        VALUES (v_expense.id, v_split.user_id, v_split.amount);
    END LOOP;

    RETURN v_expense;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.add_expense_with_splits(uuid,uuid,numeric,text,text,text,text,text,split_input[],numeric,text,text,timestamptz) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.add_expense_with_splits(uuid,uuid,numeric,text,text,text,text,text,split_input[],numeric,text,text,timestamptz) TO authenticated;

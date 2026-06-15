-- Atomically instantiate a due recurring expense and advance its template.
-- This prevents duplicate one-off expenses when multiple clients see the same
-- due template or when the app is interrupted between create and advance.

CREATE OR REPLACE FUNCTION public.create_recurring_expense_instance(
    p_template_id uuid,
    p_expected_next_occurrence timestamptz,
    p_new_next_occurrence timestamptz
)
RETURNS public.expenses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_template public.expenses;
    v_instance public.expenses;
BEGIN
    UPDATE public.expenses
    SET next_occurrence_date = p_new_next_occurrence
    WHERE id = p_template_id
      AND recurrence <> 'none'
      AND next_occurrence_date = p_expected_next_occurrence
      AND public.is_group_member(group_id)
    RETURNING * INTO v_template;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.splits WHERE expense_id = p_template_id
    ) THEN
        RETURN NULL;
    END IF;

    INSERT INTO public.expenses (
        group_id, paid_by, amount, title, category, currency, notes, receipt_url,
        original_amount, original_currency, recurrence, next_occurrence_date
    )
    VALUES (
        v_template.group_id, v_template.paid_by, v_template.amount,
        v_template.title, v_template.category, v_template.currency,
        v_template.notes, NULL, v_template.original_amount,
        v_template.original_currency, 'none', NULL
    )
    RETURNING * INTO v_instance;

    INSERT INTO public.splits (expense_id, user_id, amount)
    SELECT v_instance.id, user_id, amount
    FROM public.splits
    WHERE expense_id = p_template_id;

    RETURN v_instance;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_recurring_expense_instance(uuid, timestamptz, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_recurring_expense_instance(uuid, timestamptz, timestamptz) TO authenticated;

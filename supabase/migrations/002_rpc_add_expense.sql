-- =============================================================================
-- 002_rpc_add_expense.sql
-- RPC: add_expense_with_splits
-- Inserts an expense and all of its splits atomically.
-- Called from ExpenseService.swift so the iOS client never does multi-step writes.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Input type for a single split row
-- ---------------------------------------------------------------------------
create type public.split_input as (
    user_id uuid,
    amount  numeric(10, 2)
);

-- ---------------------------------------------------------------------------
-- add_expense_with_splits
--
-- Parameters
--   p_group_id    — group the expense belongs to
--   p_paid_by     — auth.uid() of the payer (must match the calling user)
--   p_amount      — total expense amount; must equal sum of split amounts
--   p_description — human-readable label
--   p_category    — category string (e.g. 'food', 'transport', 'other')
--   p_receipt_url — optional storage URL for receipt image
--   p_splits      — array of split_input; amounts must sum to p_amount
--
-- Returns the newly created expense row.
-- Raises exceptions for invalid input so the caller gets a clean error.
-- ---------------------------------------------------------------------------
create or replace function public.add_expense_with_splits(
    p_group_id    uuid,
    p_paid_by     uuid,
    p_amount      numeric(10, 2),
    p_description text,
    p_category    text,
    p_receipt_url text          default null,
    p_splits      split_input[] default array[]::split_input[]
)
returns public.expenses
language plpgsql
security definer          -- runs as the function owner, bypasses per-row RLS inside
set search_path = public  -- prevent search_path injection
as $$
declare
    v_expense     public.expenses;
    v_splits_sum  numeric(10, 2);
    v_split       public.split_input;
begin
    -- ── Guard: caller must be the payer ─────────────────────────────────────
    if auth.uid() <> p_paid_by then
        raise exception 'paid_by must match the authenticated user'
            using errcode = 'insufficient_privilege';
    end if;

    -- ── Guard: caller must be a group member ─────────────────────────────────
    if not public.is_group_member(p_group_id) then
        raise exception 'caller is not a member of group %', p_group_id
            using errcode = 'insufficient_privilege';
    end if;

    -- ── Guard: splits must sum to total ──────────────────────────────────────
    select coalesce(sum(s.amount), 0)
    into   v_splits_sum
    from   unnest(p_splits) as s;

    if round(v_splits_sum, 2) <> round(p_amount, 2) then
        raise exception 'split amounts (%) do not sum to expense total (%)',
            v_splits_sum, p_amount
            using errcode = 'check_violation';
    end if;

    -- ── Insert expense ────────────────────────────────────────────────────────
    insert into public.expenses (group_id, paid_by, amount, description, category, receipt_url)
    values (p_group_id, p_paid_by, p_amount, p_description, p_category, p_receipt_url)
    returning * into v_expense;

    -- ── Insert splits ─────────────────────────────────────────────────────────
    foreach v_split in array p_splits loop
        insert into public.splits (expense_id, user_id, amount)
        values (v_expense.id, v_split.user_id, v_split.amount);
    end loop;

    return v_expense;
end;
$$;

-- Only authenticated users can call this function
revoke execute on function public.add_expense_with_splits from public;
grant  execute on function public.add_expense_with_splits to authenticated;

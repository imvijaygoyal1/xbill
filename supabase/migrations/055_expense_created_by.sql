-- 055_expense_created_by.sql
--
-- BOOKKEEPER FLOW: let any group member record an expense paid by another member.
--
-- Why: `paid_by` was doing two jobs — "who spent the money" and "who may touch this row". Four
-- separate places enforced `auth.uid() = paid_by` (INSERT/UPDATE/DELETE policies and the RPC), so
-- a member could not record an expense someone else paid, and could not correct a mistyped payer:
-- the UPDATE's WITH CHECK evaluates the NEW row, so changing `paid_by` always failed with
-- "new row violates row-level security policy for table expenses". Deleting and re-adding hit the
-- RPC guard instead. Reported from live use 2026-09-08.
--
-- `settlements` already solved this shape in migration 041 by separating `recorded_by` from the
-- parties. This gives `expenses` the same separation.
--
-- ⚠️ NO EXISTING ROW IS WRITTEN. `created_by` is nullable with no backfill, so the 45 live
-- expenses keep NULL. `auth.uid() = created_by` is then NULL for them, the OR falls through to the
-- `paid_by` arm, and legacy rows behave EXACTLY as they do today. This is deliberate — the owner
-- asked that existing expenses not be touched, and it also means the change cannot corrupt history.

-- ── 1. The column ────────────────────────────────────────────────────────────
alter table public.expenses
    add column if not exists created_by uuid references auth.users(id) on delete set null;

comment on column public.expenses.created_by is
    'Who recorded this expense, which may differ from paid_by (bookkeeper flow). NULL on rows '
    'predating migration 055; those fall back to paid_by for all authorisation. Always set from '
    'auth.uid() server-side — never accepted from the client.';

create index if not exists expenses_created_by_idx on public.expenses (created_by);

-- ── 2. Policies ──────────────────────────────────────────────────────────────
-- The payer must be a member of the group. Previously implied by `auth.uid() = paid_by` plus the
-- membership check; dropping that arm removes the guarantee, so it is now explicit. Membership,
-- not ACTIVE membership — matching the settlements decision, so an expense can still name someone
-- who has since left the group.
create or replace function public.is_group_member_of(p_group_id uuid, p_user_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.group_members gm
        where gm.group_id = p_group_id and gm.user_id = p_user_id
    );
$$;
revoke execute on function public.is_group_member_of(uuid, uuid) from anon;

drop policy if exists "expenses: group members can insert" on public.expenses;
create policy "expenses: members record their own or another's"
    on public.expenses for insert to authenticated
    with check (
        public.is_group_member(group_id)
        and created_by = auth.uid()
        and public.is_group_member_of(group_id, paid_by)
    );

drop policy if exists "expenses: payer can update" on public.expenses;
create policy "expenses: payer or recorder can update"
    on public.expenses for update to authenticated
    using  (public.is_group_member(group_id)
            and (auth.uid() = paid_by or auth.uid() = created_by))
    with check (public.is_group_member(group_id)
            and (auth.uid() = paid_by or auth.uid() = created_by)
            and public.is_group_member_of(group_id, paid_by));

drop policy if exists "expenses: payer can delete" on public.expenses;
create policy "expenses: payer or recorder can delete"
    on public.expenses for delete to authenticated
    using (auth.uid() = paid_by or auth.uid() = created_by);

-- ── 3. add_expense_with_splits ───────────────────────────────────────────────
-- SECURITY DEFINER, so it bypasses RLS and its own guards ARE the authorisation.
--
-- The 13-argument signature is UNCHANGED, so CREATE OR REPLACE genuinely replaces rather than
-- creating a second overload. (H-11 has bitten this schema three times — 013, 027, 054 — every
-- time from changing an argument list with CREATE OR REPLACE. Verify `count(*) = 1` after deploy.)
--
-- Three changes:
--   a. `auth.uid() <> p_paid_by` is REPLACED, not merely relaxed. It was also **inert for an
--      anonymous caller** (SECDEF-03): NULL <> uuid evaluates to NULL, not TRUE, so the IF never
--      fired and only the membership check below stopped an unauthenticated write. The new
--      explicit NULL check closes that.
--   b. the named payer must be a member of the group — previously implied by the guard removed above.
--   c. created_by is stamped from auth.uid(), never from the client.
-- ⚠️ The eight DEFAULTs below are load-bearing and must be reproduced verbatim. PostgREST resolves
-- an RPC by the exact key set it receives, and migration 045 added these so a client omitting an
-- optional key still resolves (the SPLIT-04 fix — a nil that Swift's synthesized Encodable dropped
-- produced `PGRST202 Could not find the function` for a real user). Omitting them here failed the
-- first deploy attempt outright with `cannot remove parameter defaults from existing function`
-- (SQLSTATE 42P13) — Postgres refuses, which is the only reason this was caught before shipping.
create or replace function public.add_expense_with_splits(
    p_group_id uuid,
    p_paid_by uuid,
    p_amount numeric,
    p_title text,
    p_category text,
    p_currency text DEFAULT 'USD'::text,
    p_notes text DEFAULT NULL::text,
    p_receipt_url text DEFAULT NULL::text,
    p_splits public.split_input[] DEFAULT ARRAY[]::public.split_input[],
    p_original_amount numeric DEFAULT NULL::numeric,
    p_original_currency text DEFAULT NULL::text,
    p_recurrence text DEFAULT 'none'::text,
    p_next_occurrence_date timestamptz DEFAULT NULL::timestamptz
) returns public.expenses
language plpgsql security definer set search_path = public as $$
DECLARE
    v_caller     uuid := auth.uid();
    v_expense    public.expenses;
    v_splits_sum numeric(10, 2);
    v_split      public.split_input;
BEGIN
    -- SECDEF-03: explicit, because `v_caller <> p_paid_by` is NULL for an anonymous caller and
    -- therefore never raises. A guard that cannot fire is not a guard.
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'You need to be signed in' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_group_member(p_group_id) THEN
        RAISE EXCEPTION 'caller is not a member of group %', p_group_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- The bookkeeper flow: p_paid_by may be someone other than the caller, but must be in the group.
    IF NOT public.is_group_member_of(p_group_id, p_paid_by) THEN
        RAISE EXCEPTION 'the named payer is not a member of group %', p_group_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT COALESCE(SUM(s.amount), 0) INTO v_splits_sum FROM unnest(p_splits) AS s;
    IF ROUND(v_splits_sum, 2) <> ROUND(p_amount, 2) THEN
        RAISE EXCEPTION 'split amounts (%) do not sum to expense total (%)', v_splits_sum, p_amount
            USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO public.expenses (
        group_id, paid_by, created_by, amount, title, category, currency, notes, receipt_url,
        original_amount, original_currency, recurrence, next_occurrence_date
    ) VALUES (
        p_group_id, p_paid_by, v_caller, p_amount, p_title, p_category, p_currency, p_notes,
        p_receipt_url, p_original_amount, p_original_currency, p_recurrence, p_next_occurrence_date
    ) RETURNING * INTO v_expense;

    FOREACH v_split IN ARRAY p_splits LOOP
        INSERT INTO public.splits (expense_id, user_id, amount)
        VALUES (v_expense.id, v_split.user_id, v_split.amount);
    END LOOP;

    RETURN v_expense;
END;
$$;

revoke execute on function public.add_expense_with_splits(
    uuid, uuid, numeric, text, text, text, text, text, public.split_input[],
    numeric, text, text, timestamptz) from anon;

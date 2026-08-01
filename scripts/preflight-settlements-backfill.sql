-- PRE-FLIGHT verification for migration 041 (settlements ledger).
--
-- Run this BEFORE `supabase db push`. It is strictly read-only and does not reference
-- `public.settlements` at all, so it runs against a production database on which the table
-- does not yet exist.
--
-- Why a pre-flight variant exists at all
-- --------------------------------------
-- `verify-settlements-backfill.sql` can only run AFTER the migration has created the table
-- and inserted the backfill. By then the table exists, which permanently disarms the
-- backfill's `NOT EXISTS (SELECT 1 FROM public.settlements)` re-run guard, and there is no
-- rollback. A check that can only run past the point of no return is a post-hoc
-- confirmation, not a gate. This file is the gate: it simulates the backfill in a CTE with
-- exactly the migration's own WHERE clause and compares the two balance models before
-- anything is written.
--
-- Old model: unsettled splits only. New model: all splits, minus settlements.
-- Every row returned is a (group, user) whose balance would change. Expect ZERO rows.
--
-- Two aggregation properties matter, and both were defects at some point:
--
-- 1. Each side is aggregated to ONE row per key BEFORE the join. The first version of the
--    post-migration script UNION ALL'd the branches and aggregated AFTER a FULL OUTER JOIN
--    on user_id -- a non-unique key -- so the join produced a cross product per user and
--    each side was double-counted by the other's branch count. Demonstrated against
--    Postgres: true old -30 vs true new -30 was reported as -60 vs -30 (false alarm), and
--    the same mechanism can make a genuine drift compare equal (3 rows x 20 = 60 vs
--    2 rows x 30 = 60), masking it.
--
-- 2. The key is (group_id, user_id), not user_id. Balances in this app are per-group -- the
--    app never sums a user across groups, and different groups can carry different
--    currencies, so a cross-group sum is not a quantity that means anything. Grouping by
--    user alone lets a user whose balance rises by X in one group and falls by X in another
--    compare equal and never surface. That is structurally the same masking bug as (1),
--    moved up a level.
WITH backfill AS (
    -- Exactly the migration's backfill SELECT (041_settlements.sql), reduced to the columns
    -- that affect a balance. `s.amount > 0` mirrors the migration's own guard, which exists
    -- because splits permit 0.00 (`CHECK (amount >= 0)`) while settlements require > 0.
    SELECT e.group_id, s.user_id AS from_user_id, e.paid_by AS to_user_id, s.amount
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE s.is_settled AND e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
       AND s.amount > 0
),
old_raw AS (
    SELECT e.group_id, e.paid_by AS user_id, s.amount AS delta
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE NOT s.is_settled AND e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
    UNION ALL
    SELECT e.group_id, s.user_id, -s.amount
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE NOT s.is_settled AND e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
),
old_balances AS (
    SELECT group_id, user_id, SUM(delta) AS delta FROM old_raw GROUP BY group_id, user_id
),
new_raw AS (
    SELECT e.group_id, e.paid_by AS user_id, s.amount AS delta
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
    UNION ALL
    SELECT e.group_id, s.user_id, -s.amount
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
    UNION ALL
    SELECT group_id, from_user_id,  amount FROM backfill
    UNION ALL
    SELECT group_id, to_user_id,   -amount FROM backfill
),
new_balances AS (
    SELECT group_id, user_id, SUM(delta) AS delta FROM new_raw GROUP BY group_id, user_id
)
SELECT COALESCE(o.group_id, n.group_id) AS group_id,
       COALESCE(o.user_id,  n.user_id)  AS user_id,
       COALESCE(o.delta, 0) AS old_balance,
       COALESCE(n.delta, 0) AS new_balance
  FROM old_balances o
  FULL OUTER JOIN new_balances n
    ON o.group_id = n.group_id AND o.user_id = n.user_id
 WHERE COALESCE(o.delta, 0) <> COALESCE(n.delta, 0);

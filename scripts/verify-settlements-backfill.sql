-- POST-MIGRATION verification for migration 041 (settlements ledger).
--
-- VALIDITY WINDOW: this script is meaningful ONLY in the window immediately after the
-- backfill runs, before any real payment is recorded. `old_balances` below still reads
-- `splits.is_settled`, which the app no longer writes. The moment a user records a genuine
-- settlement, the new model offsets that debt and the old model does not, so this script
-- reports drift for every real payment -- correctly, but uselessly. It is a one-shot
-- confirmation, not a monitor. Do not re-run it later and read a non-empty result as a bug.
--
-- PREFER THE PRE-FLIGHT. `preflight-settlements-backfill.sql` performs the same comparison
-- against a CTE that simulates the backfill, so it runs BEFORE `db push` and is a real
-- gate. This script can only run after the table exists -- and creating the table already
-- disarms the backfill's `NOT EXISTS (SELECT 1 FROM public.settlements)` re-run guard, with
-- no rollback. Run the pre-flight to decide; run this one to confirm the write landed.
--
-- Old model: unsettled splits only. New model: all splits, minus settlements.
-- Every row returned is a (group, user) whose balance changed. Expect ZERO rows.
--
-- Two aggregation properties matter, and both were defects at some point:
--
-- 1. Each side is aggregated to ONE row per key BEFORE the join. The first version of this
--    script UNION ALL'd the branches and aggregated AFTER a FULL OUTER JOIN on user_id -- a
--    non-unique key -- so the join produced a cross product per user and each side was
--    double-counted by the other's branch count. Demonstrated against Postgres: true old -30
--    vs true new -30 was reported as -60 vs -30 (false alarm), and the same mechanism can
--    make a genuine drift compare equal (3 rows x 20 = 60 vs 2 rows x 30 = 60), masking it.
--
-- 2. The key is (group_id, user_id), not user_id. Balances in this app are per-group -- the
--    app never sums a user across groups, and different groups can carry different
--    currencies, so a cross-group sum is not a quantity that means anything. Grouping by
--    user alone lets a user whose balance rises by X in one group and falls by X in another
--    compare equal and never surface. That is structurally the same masking bug as (1),
--    moved up a level.
WITH old_raw AS (
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
    SELECT group_id, from_user_id,  amount FROM public.settlements
    UNION ALL
    SELECT group_id, to_user_id,   -amount FROM public.settlements
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

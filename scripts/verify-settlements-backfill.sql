-- Old model: unsettled splits only. New model: all splits, minus settlements.
-- Every row returned is a user whose balance changed. Expect ZERO rows.
--
-- Each side is aggregated to ONE row per user BEFORE the join. The first version of this
-- script UNION ALL'd the branches and aggregated AFTER a FULL OUTER JOIN on user_id -- a
-- non-unique key -- so the join produced a cross product per user and each side was
-- double-counted by the other's branch count. Demonstrated against Postgres: true old -30
-- vs true new -30 was reported as -60 vs -30 (false alarm), and the same mechanism can make
-- a genuine drift compare equal (3 rows x 20 = 60 vs 2 rows x 30 = 60), masking it.
WITH old_raw AS (
    SELECT e.paid_by AS user_id, s.amount AS delta
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE NOT s.is_settled AND e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
    UNION ALL
    SELECT s.user_id, -s.amount
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE NOT s.is_settled AND e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
),
old_balances AS (SELECT user_id, SUM(delta) AS delta FROM old_raw GROUP BY user_id),
new_raw AS (
    SELECT e.paid_by AS user_id, s.amount AS delta
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
    UNION ALL
    SELECT s.user_id, -s.amount
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
    UNION ALL
    SELECT from_user_id,  amount FROM public.settlements
    UNION ALL
    SELECT to_user_id,   -amount FROM public.settlements
),
new_balances AS (SELECT user_id, SUM(delta) AS delta FROM new_raw GROUP BY user_id)
SELECT COALESCE(o.user_id, n.user_id) AS user_id,
       COALESCE(o.delta, 0) AS old_balance,
       COALESCE(n.delta, 0) AS new_balance
  FROM old_balances o FULL OUTER JOIN new_balances n ON o.user_id = n.user_id
 WHERE COALESCE(o.delta, 0) <> COALESCE(n.delta, 0);

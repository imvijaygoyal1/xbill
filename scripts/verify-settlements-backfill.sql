-- Old model: unsettled splits only. New model: all splits, minus settlements.
-- Every row returned is a user whose balance changed. Expect ZERO rows.
WITH old_balances AS (
    SELECT e.paid_by AS user_id, SUM(s.amount) AS delta
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE NOT s.is_settled AND e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
     GROUP BY e.paid_by
    UNION ALL
    SELECT s.user_id, -SUM(s.amount)
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE NOT s.is_settled AND e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
     GROUP BY s.user_id
),
new_balances AS (
    SELECT e.paid_by AS user_id, SUM(s.amount) AS delta
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
     GROUP BY e.paid_by
    UNION ALL
    SELECT s.user_id, -SUM(s.amount)
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
     GROUP BY s.user_id
    UNION ALL
    SELECT from_user_id, SUM(amount) FROM public.settlements GROUP BY from_user_id
    UNION ALL
    SELECT to_user_id, -SUM(amount) FROM public.settlements GROUP BY to_user_id
)
SELECT COALESCE(o.user_id, n.user_id) AS user_id,
       COALESCE(SUM(o.delta), 0) AS old_balance,
       COALESCE(SUM(n.delta), 0) AS new_balance
  FROM old_balances o FULL OUTER JOIN new_balances n ON o.user_id = n.user_id
 GROUP BY 1
HAVING COALESCE(SUM(o.delta), 0) <> COALESCE(SUM(n.delta), 0);

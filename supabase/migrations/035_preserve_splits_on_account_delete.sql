-- Preserve shared expense history when a user deletes their account.
--
-- `expenses.paid_by` already uses ON DELETE SET NULL. `splits.user_id` should
-- keep the historical participant UUID instead of cascading split deletion,
-- otherwise other group members lose ledger rows and balances can change.

ALTER TABLE public.splits
  DROP CONSTRAINT IF EXISTS splits_user_id_fkey;

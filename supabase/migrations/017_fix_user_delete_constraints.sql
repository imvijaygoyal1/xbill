-- Fix FK constraints that block auth user deletion (ON DELETE RESTRICT → SET NULL).
-- groups.created_by and expenses.paid_by must be nullable for SET NULL to work.

-- groups.created_by
ALTER TABLE public.groups
  DROP CONSTRAINT groups_created_by_fkey;
ALTER TABLE public.groups
  ALTER COLUMN created_by DROP NOT NULL;
ALTER TABLE public.groups
  ADD CONSTRAINT groups_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES auth.users (id) ON DELETE SET NULL;

-- expenses.paid_by
ALTER TABLE public.expenses
  DROP CONSTRAINT expenses_paid_by_fkey;
ALTER TABLE public.expenses
  ALTER COLUMN paid_by DROP NOT NULL;
ALTER TABLE public.expenses
  ADD CONSTRAINT expenses_paid_by_fkey
    FOREIGN KEY (paid_by) REFERENCES auth.users (id) ON DELETE SET NULL;

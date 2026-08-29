-- Read-only verification for migration 051. Writes nothing. Run after `supabase db push`.

-- 1. No NULL tokens remain, and the column is NOT NULL with a default.
SELECT count(*) AS null_tokens FROM public.expenses WHERE updated_at IS NULL;
SELECT is_nullable, column_default
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'expenses' AND column_name = 'updated_at';

-- 2. Exactly ONE update_expense_with_splits exists. Two means the DROP failed and an orphaned
--    overload is executable -- defect H-11.
SELECT count(*) AS overloads, max(pg_get_function_identity_arguments(p.oid)) AS signature
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'update_expense_with_splits';

-- 3. anon cannot execute it; authenticated can.
SELECT has_function_privilege('anon', p.oid, 'EXECUTE')          AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'update_expense_with_splits';

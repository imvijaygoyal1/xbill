-- Migration 054: drop two orphaned RPC overloads (H-11, third occurrence).
--
-- Found by the SECURITY DEFINER sweep of 2026-08-31: two functions appeared TWICE in
-- `pg_proc`, each with an older signature still executable alongside the current one.
--
--     add_expense_with_splits            9 args (5 required)  and  13 args (5 required)
--     create_recurring_expense_instance  1 arg  (1 required)  and   3 args (3 required)
--
-- This is defect H-11 exactly. It has already caused a production incident here: migration 013
-- changed `add_expense_with_splits`'s argument list with CREATE OR REPLACE, which does NOT replace
-- a function when the arguments differ — it creates a second overload — and PostgREST was left
-- choosing between candidates. Migration 027 dropped *a* stale overload; CLAUDE.md reads as though
-- that settled it. It did not: a 9-argument version is still executable today.
--
-- ## Why dropping these is safe — verified, not assumed
--
-- PostgREST resolves an RPC by the exact set of keys in the request body, so an overload is only
-- reachable if a client can produce a payload matching it.
--
-- **add_expense_with_splits.** The 9-arg signature has no `p_recurrence`. The client's
-- `AddExpenseParams` declares `recurrence` as a NON-optional `String`, so it is present in every
-- request — even though the struct uses Swift's synthesized `Encodable`, which omits nils (the
-- SPLIT-04 trap; it is harmless here only because the 13-arg function defaults all eight optional
-- parameters). A payload carrying `p_recurrence` cannot match the 9-arg function.
--
--   Checked in git rather than assumed: `case recurrence = "p_recurrence"` was introduced in
--   e008977 (2026-04-13), and `git merge-base --is-ancestor e008977 48608a2` confirms it predates
--   the 1.1 bump — therefore every build ever shipped (1.0 … 1.5) sends it.
--
-- **create_recurring_expense_instance.** The client sends three keys (`p_template_id`,
-- `p_expected_next_occurrence`, `p_new_next_occurrence`), introduced in e9be353 (2026-06-15),
-- likewise an ancestor of 1.1. The 1-arg version takes only `p_template_id` and has no defaults,
-- so a 3-key payload cannot resolve to it.
--
-- So neither orphan is reachable from any shipped client. They are latent, not live — but latent
-- is exactly what H-11 was before it wasn't, and an unreachable function that silently DROPS
-- multi-currency and recurrence data is a bad thing to leave executable next to the real one.
--
-- ## Why this is a DROP with an explicit argument list
--
-- `DROP FUNCTION name(args)` names the overload precisely. A bare `DROP FUNCTION name` errors when
-- more than one exists rather than guessing, which is the behaviour we want; being explicit means
-- this migration cannot remove the wrong one even if the set of overloads changes before it runs.
--
-- If either DROP finds nothing (someone dropped it first), `IF EXISTS` makes that a no-op instead
-- of failing the deploy.

DROP FUNCTION IF EXISTS public.add_expense_with_splits(
    uuid,                  -- p_group_id
    uuid,                  -- p_paid_by
    numeric,               -- p_amount
    text,                  -- p_title
    text,                  -- p_category
    text,                  -- p_currency
    text,                  -- p_notes
    text,                  -- p_receipt_url
    public.split_input[]   -- p_splits
);

DROP FUNCTION IF EXISTS public.create_recurring_expense_instance(
    uuid                   -- p_template_id
);

-- Leave a note where the next person will actually be standing when they change one of these.
COMMENT ON FUNCTION public.add_expense_with_splits(
    uuid, uuid, numeric, text, text, text, text, text, public.split_input[],
    numeric, text, text, timestamptz) IS
    'Atomic expense + splits insert. THIS IS THE ONLY OVERLOAD — a 9-argument orphan was dropped in '
    '054 (H-11, third occurrence). Never change this argument list with CREATE OR REPLACE: with a '
    'different signature that CREATES A SECOND OVERLOAD and leaves PostgREST choosing. Always '
    'DROP + CREATE, as migration 051 does for update_expense_with_splits.';

COMMENT ON FUNCTION public.create_recurring_expense_instance(uuid, timestamptz, timestamptz) IS
    'Atomically claims a recurring template occurrence and creates the instance. THIS IS THE ONLY '
    'OVERLOAD — a 1-argument orphan was dropped in 054. Change the signature with DROP + CREATE, '
    'never CREATE OR REPLACE.';

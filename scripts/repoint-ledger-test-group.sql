-- Re-points the Ledger Test 🧪 fixture at a different "you" account.
--
-- Use when the phone is signed in as someone other than the account the fixture was built
-- around. Edit TARGET_EMAIL below, run it, then pull-to-refresh in the app.
-- (`supabase db query` runs plain SQL, not psql, so there are no \set variables.)
--
-- It swaps the target account into every place the previous "you" appeared — membership,
-- expense payer, splits, and settlement from/to/recorded_by — so all three test roles
-- (debtor, creditor, non-party) and both sides of the delete gate are preserved exactly.
--
-- Only touches group bbbb0001-…, so Tokyo Trip and real groups cannot be affected.

WITH target AS (SELECT id FROM public.profiles WHERE email = 'xbill.uitest@example.com'),  -- TARGET_EMAIL
     old AS (
       -- the current "you": the member who is neither Alice nor Bob
       SELECT gm.user_id AS id FROM public.group_members gm
        WHERE gm.group_id = 'bbbb0001-0000-0000-0000-000000000001'
          AND gm.user_id NOT IN (
              SELECT id FROM public.profiles
               WHERE email IN ('alice.seed@xbill.vijaygoyal.org','bob.seed@xbill.vijaygoyal.org'))
        LIMIT 1)
, m AS (
  UPDATE public.group_members gm SET user_id = (SELECT id FROM target)
   WHERE gm.group_id = 'bbbb0001-0000-0000-0000-000000000001'
     AND gm.user_id = (SELECT id FROM old)
     AND (SELECT id FROM target) IS DISTINCT FROM (SELECT id FROM old)
  RETURNING 1)
, e AS (
  UPDATE public.expenses SET paid_by = (SELECT id FROM target)
   WHERE group_id = 'bbbb0001-0000-0000-0000-000000000001' AND paid_by = (SELECT id FROM old)
  RETURNING 1)
, s AS (
  UPDATE public.splits SET user_id = (SELECT id FROM target)
   WHERE user_id = (SELECT id FROM old)
     AND expense_id IN (SELECT id FROM public.expenses WHERE group_id='bbbb0001-0000-0000-0000-000000000001')
  RETURNING 1)
, sf AS (
  UPDATE public.settlements SET from_user_id = (SELECT id FROM target)
   WHERE group_id='bbbb0001-0000-0000-0000-000000000001' AND from_user_id = (SELECT id FROM old) RETURNING 1)
, st AS (
  UPDATE public.settlements SET to_user_id = (SELECT id FROM target)
   WHERE group_id='bbbb0001-0000-0000-0000-000000000001' AND to_user_id = (SELECT id FROM old) RETURNING 1)
, sr AS (
  UPDATE public.settlements SET recorded_by = (SELECT id FROM target)
   WHERE group_id='bbbb0001-0000-0000-0000-000000000001' AND recorded_by = (SELECT id FROM old) RETURNING 1)
SELECT (SELECT count(*) FROM m)  AS members_moved,
       (SELECT count(*) FROM e)  AS expenses_moved,
       (SELECT count(*) FROM s)  AS splits_moved,
       (SELECT count(*) FROM sf) + (SELECT count(*) FROM st) + (SELECT count(*) FROM sr) AS settlement_fields_moved;

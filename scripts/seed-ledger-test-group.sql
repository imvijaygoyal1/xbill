-- Device-verification fixture for the settlements ledger (migration 041).
--
-- Creates ONE new group owned by imvijaygoyal@gmail.com so the ledger can be exercised
-- while signed in as yourself. Deliberately does NOT touch the Tokyo Trip seed, which is
-- App Store review data.
--
-- All ids are deterministic and prefixed bbbb…, so scripts/teardown-ledger-test-group.sql
-- removes exactly what this created and nothing else. Re-running this is safe: every insert
-- is ON CONFLICT DO NOTHING against those fixed ids.
--
-- Resulting Settle Up, signed in as Vijay:
--   Vijay      -> Alice Chen   $7.00   (you are the DEBTOR   — normal path, payment buttons)
--   Bob Patel  -> Vijay        $8.00   (you are the CREDITOR — the REV-01 path)
--   Bob Patel  -> Alice Chen  $15.50   (you are NEITHER      — dimmed, no button)
-- Recent Payments:
--   Vijay paid Alice Chen $3.00  · recorded by Alice Chen  -> you CANNOT delete
--   Bob Patel paid Vijay  $2.00  · recorded by Vijay       -> you CAN delete
-- Net balances: Vijay +1.00, Alice +22.50, Bob -23.50  (sums to 0)

WITH ids AS (
    SELECT
        (SELECT id FROM public.profiles WHERE email = 'imvijaygoyal@gmail.com')          AS vijay,
        (SELECT id FROM public.profiles WHERE email = 'alice.seed@xbill.vijaygoyal.org') AS alice,
        (SELECT id FROM public.profiles WHERE email = 'bob.seed@xbill.vijaygoyal.org')   AS bob
)
INSERT INTO public.groups (id, name, emoji, created_by, is_archived, currency)
SELECT 'bbbb0001-0000-0000-0000-000000000001', 'Ledger Test 🧪', '🧪', vijay, false, 'USD' FROM ids
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.group_members (group_id, user_id, is_active)
SELECT 'bbbb0001-0000-0000-0000-000000000001', u, true
  FROM (SELECT unnest(ARRAY[
            (SELECT id FROM public.profiles WHERE email = 'imvijaygoyal@gmail.com'),
            (SELECT id FROM public.profiles WHERE email = 'alice.seed@xbill.vijaygoyal.org'),
            (SELECT id FROM public.profiles WHERE email = 'bob.seed@xbill.vijaygoyal.org')]) AS u) m
ON CONFLICT DO NOTHING;

-- E1  Dinner $30 paid by Vijay, split three ways -> Alice and Bob each owe Vijay 10
INSERT INTO public.expenses (id, group_id, paid_by, amount, title, category, currency)
SELECT 'bbbb0002-0000-0000-0000-000000000001', 'bbbb0001-0000-0000-0000-000000000001',
       (SELECT id FROM public.profiles WHERE email = 'imvijaygoyal@gmail.com'),
       30.00, 'Dinner', 'food', 'USD'
ON CONFLICT (id) DO NOTHING;

-- E2  Hotel $60 paid by Alice, split three ways -> Vijay and Bob each owe Alice 20
INSERT INTO public.expenses (id, group_id, paid_by, amount, title, category, currency)
SELECT 'bbbb0002-0000-0000-0000-000000000002', 'bbbb0001-0000-0000-0000-000000000001',
       (SELECT id FROM public.profiles WHERE email = 'alice.seed@xbill.vijaygoyal.org'),
       60.00, 'Hotel', 'accommodation', 'USD'
ON CONFLICT (id) DO NOTHING;

-- E3  Coffee $9 paid by Bob, split between Alice and Bob only.
--     Vijay is NOT a participant, which is what produces the third-party row.
INSERT INTO public.expenses (id, group_id, paid_by, amount, title, category, currency)
SELECT 'bbbb0002-0000-0000-0000-000000000003', 'bbbb0001-0000-0000-0000-000000000001',
       (SELECT id FROM public.profiles WHERE email = 'bob.seed@xbill.vijaygoyal.org'),
       9.00, 'Coffee', 'food', 'USD'
ON CONFLICT (id) DO NOTHING;

-- Splits. The payer's own share is included, matching how the app writes them; balance
-- computation skips it.
INSERT INTO public.splits (id, expense_id, user_id, amount, is_settled)
SELECT v.id, v.expense_id, v.user_id, v.amount, false FROM (VALUES
  ('bbbb0003-0000-0000-0000-000000000001'::uuid, 'bbbb0002-0000-0000-0000-000000000001'::uuid, (SELECT id FROM public.profiles WHERE email='imvijaygoyal@gmail.com'),          10.00),
  ('bbbb0003-0000-0000-0000-000000000002'::uuid, 'bbbb0002-0000-0000-0000-000000000001'::uuid, (SELECT id FROM public.profiles WHERE email='alice.seed@xbill.vijaygoyal.org'), 10.00),
  ('bbbb0003-0000-0000-0000-000000000003'::uuid, 'bbbb0002-0000-0000-0000-000000000001'::uuid, (SELECT id FROM public.profiles WHERE email='bob.seed@xbill.vijaygoyal.org'),   10.00),
  ('bbbb0003-0000-0000-0000-000000000004'::uuid, 'bbbb0002-0000-0000-0000-000000000002'::uuid, (SELECT id FROM public.profiles WHERE email='imvijaygoyal@gmail.com'),          20.00),
  ('bbbb0003-0000-0000-0000-000000000005'::uuid, 'bbbb0002-0000-0000-0000-000000000002'::uuid, (SELECT id FROM public.profiles WHERE email='alice.seed@xbill.vijaygoyal.org'), 20.00),
  ('bbbb0003-0000-0000-0000-000000000006'::uuid, 'bbbb0002-0000-0000-0000-000000000002'::uuid, (SELECT id FROM public.profiles WHERE email='bob.seed@xbill.vijaygoyal.org'),   20.00),
  ('bbbb0003-0000-0000-0000-000000000007'::uuid, 'bbbb0002-0000-0000-0000-000000000003'::uuid, (SELECT id FROM public.profiles WHERE email='alice.seed@xbill.vijaygoyal.org'),  4.50),
  ('bbbb0003-0000-0000-0000-000000000008'::uuid, 'bbbb0002-0000-0000-0000-000000000003'::uuid, (SELECT id FROM public.profiles WHERE email='bob.seed@xbill.vijaygoyal.org'),    4.50)
) AS v(id, expense_id, user_id, amount)
ON CONFLICT (id) DO NOTHING;

-- Two pre-existing payments, so Recent Payments is populated and the recorder-only delete
-- gate can be tested in BOTH directions from a single signed-in account.
INSERT INTO public.settlements (id, group_id, from_user_id, to_user_id, amount, currency, recorded_by, created_at)
SELECT v.id, 'bbbb0001-0000-0000-0000-000000000001', v.from_id, v.to_id, v.amount, 'USD', v.rec, v.at FROM (VALUES
  -- recorded by Vijay -> deletable by Vijay
  ('bbbb0004-0000-0000-0000-000000000001'::uuid,
   (SELECT id FROM public.profiles WHERE email='bob.seed@xbill.vijaygoyal.org'),
   (SELECT id FROM public.profiles WHERE email='imvijaygoyal@gmail.com'), 2.00,
   (SELECT id FROM public.profiles WHERE email='imvijaygoyal@gmail.com'), now() - interval '2 hours'),
  -- recorded by Alice -> NOT deletable by Vijay
  ('bbbb0004-0000-0000-0000-000000000002'::uuid,
   (SELECT id FROM public.profiles WHERE email='imvijaygoyal@gmail.com'),
   (SELECT id FROM public.profiles WHERE email='alice.seed@xbill.vijaygoyal.org'), 3.00,
   (SELECT id FROM public.profiles WHERE email='alice.seed@xbill.vijaygoyal.org'), now() - interval '1 hour')
) AS v(id, from_id, to_id, amount, rec, at)
ON CONFLICT (id) DO NOTHING;

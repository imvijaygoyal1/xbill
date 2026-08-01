-- Stable multi-member fixture for the settlements-ledger UI regression tests.
--
-- WHY THIS EXISTS
-- `scripts/seed-ui-test-data.sh` seeds SeedActive-Regression / SeedArchived-Regression with the
-- owner as the ONLY member. A single-member group can never carry a debt, so Settle Up there
-- always renders "All Settled Up!" — which is why the settle-up regression test could only ever
-- assert the empty state, and why the entire settlements ledger shipped with no UI coverage.
-- Exercising it needs a group where the test account genuinely owes and is owed.
--
-- Name follows the SeedActive/SeedArchived convention deliberately: `seed-ui-test-data.sh`
-- documents these names as sitting OUTSIDE the disposable prefixes in
-- `purge-ui-test-groups.sh`, so a routine purge cannot delete the fixtures a regression run
-- depends on. Do not rename it to a `UITest-`/`ArchiveTest-` prefix.
--
-- Ids are deterministic and prefixed cccc… (the device fixture in
-- `seed-ledger-test-group.sql` uses bbbb…), so the two never collide and this one can be
-- removed precisely. Re-running is safe: every insert is ON CONFLICT DO NOTHING.
--
-- RESULTING SETTLE UP, signed in as xbill.uitest@example.com — one row of each kind:
--   xbill.uitest -> Alice Chen   $7.00   DEBTOR    — party, Record Payment shown
--   Bob Patel    -> xbill.uitest $8.00   CREDITOR  — party, the REV-01 path; whole dollars, so
--                                                    the sheet's prefill must read "8.00" not "8"
--   Bob Patel    -> Alice Chen  $15.50   NON-PARTY — dimmed, no button, caption instead
-- RECENT PAYMENTS — both sides of the delete gate from one signed-in account:
--   Bob Patel paid xbill.uitest  $2.00 · recorded by xbill.uitest -> CAN delete
--   xbill.uitest paid Alice Chen $3.00 · recorded by Alice Chen   -> CANNOT delete

WITH ids AS (
    SELECT
        (SELECT id FROM public.profiles WHERE email = 'xbill.uitest@example.com')          AS uitest,
        (SELECT id FROM public.profiles WHERE email = 'alice.seed@xbill.vijaygoyal.org')   AS alice,
        (SELECT id FROM public.profiles WHERE email = 'bob.seed@xbill.vijaygoyal.org')     AS bob
)
INSERT INTO public.groups (id, name, emoji, created_by, is_archived, currency)
SELECT 'cccc0001-0000-0000-0000-000000000001', 'SeedLedger-Regression', 'L', uitest, false, 'USD'
  FROM ids
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.group_members (group_id, user_id, is_active)
SELECT 'cccc0001-0000-0000-0000-000000000001', u, true
  FROM (SELECT unnest(ARRAY[
            (SELECT id FROM public.profiles WHERE email = 'xbill.uitest@example.com'),
            (SELECT id FROM public.profiles WHERE email = 'alice.seed@xbill.vijaygoyal.org'),
            (SELECT id FROM public.profiles WHERE email = 'bob.seed@xbill.vijaygoyal.org')]) AS u) m
ON CONFLICT DO NOTHING;

-- E1  Dinner $30 paid by the test account, split three ways -> Alice and Bob each owe it 10
INSERT INTO public.expenses (id, group_id, paid_by, amount, title, category, currency)
SELECT 'cccc0002-0000-0000-0000-000000000001', 'cccc0001-0000-0000-0000-000000000001',
       (SELECT id FROM public.profiles WHERE email = 'xbill.uitest@example.com'),
       30.00, 'Dinner', 'food', 'USD'
ON CONFLICT (id) DO NOTHING;

-- E2  Hotel $60 paid by Alice, split three ways -> the test account and Bob each owe Alice 20
INSERT INTO public.expenses (id, group_id, paid_by, amount, title, category, currency)
SELECT 'cccc0002-0000-0000-0000-000000000002', 'cccc0001-0000-0000-0000-000000000001',
       (SELECT id FROM public.profiles WHERE email = 'alice.seed@xbill.vijaygoyal.org'),
       60.00, 'Hotel', 'accommodation', 'USD'
ON CONFLICT (id) DO NOTHING;

-- E3  Coffee $9 paid by Bob, split between Alice and Bob only. The test account is NOT a
--     participant — this is what produces the non-party row and its caption.
INSERT INTO public.expenses (id, group_id, paid_by, amount, title, category, currency)
SELECT 'cccc0002-0000-0000-0000-000000000003', 'cccc0001-0000-0000-0000-000000000001',
       (SELECT id FROM public.profiles WHERE email = 'bob.seed@xbill.vijaygoyal.org'),
       9.00, 'Coffee', 'food', 'USD'
ON CONFLICT (id) DO NOTHING;

-- Splits. The payer's own share is included, matching how the app writes them; balance
-- computation skips it.
INSERT INTO public.splits (id, expense_id, user_id, amount, is_settled)
SELECT v.id, v.expense_id, v.user_id, v.amount, false FROM (VALUES
  ('cccc0003-0000-0000-0000-000000000001'::uuid, 'cccc0002-0000-0000-0000-000000000001'::uuid, (SELECT id FROM public.profiles WHERE email='xbill.uitest@example.com'),        10.00),
  ('cccc0003-0000-0000-0000-000000000002'::uuid, 'cccc0002-0000-0000-0000-000000000001'::uuid, (SELECT id FROM public.profiles WHERE email='alice.seed@xbill.vijaygoyal.org'), 10.00),
  ('cccc0003-0000-0000-0000-000000000003'::uuid, 'cccc0002-0000-0000-0000-000000000001'::uuid, (SELECT id FROM public.profiles WHERE email='bob.seed@xbill.vijaygoyal.org'),   10.00),
  ('cccc0003-0000-0000-0000-000000000004'::uuid, 'cccc0002-0000-0000-0000-000000000002'::uuid, (SELECT id FROM public.profiles WHERE email='xbill.uitest@example.com'),        20.00),
  ('cccc0003-0000-0000-0000-000000000005'::uuid, 'cccc0002-0000-0000-0000-000000000002'::uuid, (SELECT id FROM public.profiles WHERE email='alice.seed@xbill.vijaygoyal.org'), 20.00),
  ('cccc0003-0000-0000-0000-000000000006'::uuid, 'cccc0002-0000-0000-0000-000000000002'::uuid, (SELECT id FROM public.profiles WHERE email='bob.seed@xbill.vijaygoyal.org'),   20.00),
  ('cccc0003-0000-0000-0000-000000000007'::uuid, 'cccc0002-0000-0000-0000-000000000003'::uuid, (SELECT id FROM public.profiles WHERE email='alice.seed@xbill.vijaygoyal.org'),  4.50),
  ('cccc0003-0000-0000-0000-000000000008'::uuid, 'cccc0002-0000-0000-0000-000000000003'::uuid, (SELECT id FROM public.profiles WHERE email='bob.seed@xbill.vijaygoyal.org'),    4.50)
) AS v(id, expense_id, user_id, amount)
ON CONFLICT (id) DO NOTHING;

-- Two pre-existing payments so Recent Payments is populated and the recorder-only delete gate
-- can be asserted in BOTH directions from a single signed-in account.
INSERT INTO public.settlements (id, group_id, from_user_id, to_user_id, amount, currency, recorded_by, created_at)
SELECT v.id, 'cccc0001-0000-0000-0000-000000000001', v.from_id, v.to_id, v.amount, 'USD', v.rec, v.at FROM (VALUES
  -- recorded by the test account -> deletable by it
  ('cccc0004-0000-0000-0000-000000000001'::uuid,
   (SELECT id FROM public.profiles WHERE email='bob.seed@xbill.vijaygoyal.org'),
   (SELECT id FROM public.profiles WHERE email='xbill.uitest@example.com'), 2.00,
   (SELECT id FROM public.profiles WHERE email='xbill.uitest@example.com'), now() - interval '2 hours'),
  -- recorded by Alice -> NOT deletable by the test account
  ('cccc0004-0000-0000-0000-000000000002'::uuid,
   (SELECT id FROM public.profiles WHERE email='xbill.uitest@example.com'),
   (SELECT id FROM public.profiles WHERE email='alice.seed@xbill.vijaygoyal.org'), 3.00,
   (SELECT id FROM public.profiles WHERE email='alice.seed@xbill.vijaygoyal.org'), now() - interval '1 hour')
) AS v(id, from_id, to_id, amount, rec, at)
ON CONFLICT (id) DO NOTHING;

-- Report the resulting shape so a seeding run is self-verifying.
SELECT
  (SELECT count(*) FROM public.group_members WHERE group_id = 'cccc0001-0000-0000-0000-000000000001') AS members,
  (SELECT count(*) FROM public.expenses      WHERE group_id = 'cccc0001-0000-0000-0000-000000000001') AS expenses,
  (SELECT count(*) FROM public.splits        WHERE expense_id IN (
      SELECT id FROM public.expenses WHERE group_id = 'cccc0001-0000-0000-0000-000000000001'))        AS splits,
  (SELECT count(*) FROM public.settlements   WHERE group_id = 'cccc0001-0000-0000-0000-000000000001') AS settlements;

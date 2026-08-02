-- Restores SeedLedger-Regression to its seeded balances.
--
-- `testSettleUpLedgerWriteRegression` records a real payment and cannot undo it: deleting a
-- settlement is only reachable through a SwiftUI List swipe action, and XCUITest cannot open
-- those here (the rows are not exposed as cells, so the gesture never reaches the row). The
-- write is therefore genuine and one-way, and the fixture is reset out-of-band instead.
--
-- Deletes only settlements this fixture did not seed: seeded ids are prefixed cccc…, anything
-- else in this group was written by a test run. Scoped to the one group id, so no other group
-- can be affected.
DELETE FROM public.settlements
 WHERE group_id = 'cccc0001-0000-0000-0000-000000000001'
   AND id::text NOT LIKE 'cccc%';

SELECT count(*) AS settlements_remaining,
       count(*) FILTER (WHERE id::text NOT LIKE 'cccc%') AS unexpected_remaining
  FROM public.settlements
 WHERE group_id = 'cccc0001-0000-0000-0000-000000000001';

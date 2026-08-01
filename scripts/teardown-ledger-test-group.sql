-- Removes exactly what scripts/seed-ledger-test-group.sql created, and nothing else.
--
-- Everything it made carries a deterministic bbbb… id under one group, so this deletes by
-- that group id only. It cannot touch Tokyo Trip, your own groups, or any settlement the
-- app recorded in a different group.
--
-- NOTE: this also removes any payment YOU recorded in the Ledger Test group while testing,
-- which is intended — the whole group goes.

DELETE FROM public.settlements   WHERE group_id = 'bbbb0001-0000-0000-0000-000000000001';
DELETE FROM public.splits        WHERE expense_id IN (
    SELECT id FROM public.expenses WHERE group_id = 'bbbb0001-0000-0000-0000-000000000001');
DELETE FROM public.expenses      WHERE group_id = 'bbbb0001-0000-0000-0000-000000000001';
DELETE FROM public.group_members WHERE group_id = 'bbbb0001-0000-0000-0000-000000000001';
DELETE FROM public.groups        WHERE id       = 'bbbb0001-0000-0000-0000-000000000001';

SELECT
  (SELECT count(*) FROM public.groups      WHERE id = 'bbbb0001-0000-0000-0000-000000000001') AS groups_left,
  (SELECT count(*) FROM public.settlements WHERE group_id = 'bbbb0001-0000-0000-0000-000000000001') AS settlements_left;

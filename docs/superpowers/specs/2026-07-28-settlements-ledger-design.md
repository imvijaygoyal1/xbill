# Settlements ledger — design

**Date:** 2026-07-28
**Status:** Approved, not yet implemented
**Replaces:** the `splits.is_settled` boolean as the record of who has paid whom
**Resolves:** `REV-01` (open), and structurally eliminates `REV-02` and `REV-13`

---

## 1. Why

Settlement is currently recorded by flipping `is_settled` on individual `splits` rows. Three
defects come directly from that choice:

| Defect | Cause |
|---|---|
| `REV-01` | Only the debtor may write their own split row (`auth.uid() = user_id`), but the UI offers the button to everyone. A creditor's tap matches zero rows, silently "succeeds", is force-hidden locally, and pushes a false "you were paid" notification. |
| `REV-02` | A settlement spans N split rows, so a rejected write leaves a partially-settled state with no compensation. |
| `REV-13` | Suggestions must map to *whole* splits, so mutual debts cannot be netted — a netted $4 matches none of the debtor's splits. |

There is also no record of **who** marked something settled: `splits` has `is_settled` and
`settled_at` but no `settled_by`.

Mature bill-splitting products (Splitwise, Tricount) do not flip flags on shares. They record
payments as their own transactions and derive balances by arithmetic. This design adopts that
model.

**Timing.** The live database holds 22 splits (7 settled), 5 profiles and 1 account active in
30 days. Every settled split has a real `settled_at`; no expense has a null payer. This is the
cheapest this change will ever be.

## 2. Decisions

| # | Decision | Chosen |
|---|---|---|
| 1 | Payment amount | **Free-form**, pre-filled with the full outstanding figure |
| 2 | Who may record | **Either party only** — payer or recipient. Not other group members. |
| 3 | Who may delete | **Only the recorder** |
| 4 | Per-expense "Settled" marker | **Removed** |
| 5 | Cutover | **One-shot.** Backfill, then stop reading `is_settled`. Column retained, unused. |
| 6 | Backfill granularity | **One settlement per settled split** (7 rows) |
| 7 | Other pairs' rows in Settle Up | **Visible, greyed, no button** |

Decision 1 is what makes `REV-02` and `REV-13` structurally impossible: a payment is an
amount, not a set of split rows, so there is nothing to match and nothing to half-apply.

## 3. Data model

Migration `041_settlements.sql`:

```sql
CREATE TABLE public.settlements (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id     uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    from_user_id uuid NOT NULL,          -- payer
    to_user_id   uuid NOT NULL,          -- recipient
    amount       numeric(20,2) NOT NULL CHECK (amount > 0),
    currency     text NOT NULL,
    recorded_by  uuid NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT settlements_distinct_parties CHECK (from_user_id <> to_user_id)
);

CREATE INDEX settlements_group_created_idx ON public.settlements (group_id, created_at DESC);
CREATE INDEX settlements_group_pair_idx    ON public.settlements (group_id, from_user_id, to_user_id);
```

**No foreign key on `from_user_id`, `to_user_id`, `recorded_by`.** Migration 035 set this
precedent for `splits.user_id`: if an account is deleted, payment history must survive or
every other member's balance silently changes. The UUID is kept as a historical reference.

**Group-scoped.** Currency is copied from the group, which is locked after the first expense
(`canChangeCurrency`), so a settlement is always in the group's currency and no per-currency
netting is needed inside a group. Multi-currency arises only in the cross-group Home view,
which stays display-only and out of scope (§7). RLS reuses `is_group_member()`.

**No UPDATE path.** Corrections are delete-then-record. One fewer policy to get wrong, and the
ledger stays close to append-only.

### RLS

```sql
ALTER TABLE public.settlements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "settlements: group members read"
    ON public.settlements FOR SELECT
    USING (public.is_group_member(group_id));

CREATE POLICY "settlements: a party records their own"
    ON public.settlements FOR INSERT
    WITH CHECK (
        recorded_by = auth.uid()
        AND auth.uid() IN (from_user_id, to_user_id)
        AND public.is_group_member(group_id)
        -- Both parties must belong to the group. Without this a member could insert a payment
        -- against an arbitrary UUID. `is_active` is deliberately NOT required: someone who has
        -- left the group can still owe money that needs settling.
        AND EXISTS (SELECT 1 FROM public.group_members gm
                     WHERE gm.group_id = settlements.group_id AND gm.user_id = from_user_id)
        AND EXISTS (SELECT 1 FROM public.group_members gm
                     WHERE gm.group_id = settlements.group_id AND gm.user_id = to_user_id)
    );

CREATE POLICY "settlements: recorder deletes"
    ON public.settlements FOR DELETE
    USING (recorded_by = auth.uid());
```

No UPDATE policy is created, so no one may update.

**Known consequences of using `is_group_member()`**, which requires `is_active = true`:

- Someone removed from a group cannot record a payment, even to clear a debt they still owe.
  The other party can still record it, so no debt is stuck.
- If the account that recorded a payment is later deleted, nobody can delete that row —
  `recorded_by` matches no live user. Accepted: the row is a historical fact. Revisit only if
  it happens in practice.

The INSERT policy is decision 2 expressed in the database. Unlike the current situation, the
UI gate and the database rule state the same thing — and if they drift, the write **fails**
rather than silently matching zero rows.

## 4. Balance computation

Two independent passes replacing the settled-split filter:

```
1. Debt      — every split counts (no is_settled check):
                 payer        += amount
                 participant  -= amount
2. Payments  — for each settlement:
                 from_user_id += amount
                 to_user_id   -= amount
```

`SplitCalculator.netBalances` gains a `settlements:` parameter.
`SplitCalculator.directSettlementSuggestions` is replaced by a per-pair net that subtracts
payments and **nets mutual debts** — safe now that suggestions no longer map to whole splits.

`splits.is_settled` is read nowhere after this change.

**Over-payment is allowed and reverses the direction.** If Bob owes $20 and records a $50
payment, the arithmetic leaves Alice owing Bob $30 and Settle Up shows that row. This is
correct — it is what actually happened — and the free-form amount is what makes it
expressible. The sheet warns when the entered amount exceeds the outstanding figure, but does
not block it.

**`GroupViewModel.locallyConfirmedSettledSplitIDs` is deleted.** It exists solely to paper
over read-after-write on split flags. Inserting a row the client already holds does not need
it, and it was the mechanism that hid the `REV-01` divergence.

## 5. UI

| Surface | Change |
|---|---|
| Settle Up rows | Derived from netted debt minus payments. Rows the user is party to get a **Record Payment** button; other pairs render greyed with no button. |
| Record Payment sheet | **New file.** Amount pre-filled to the full outstanding figure, editable. Confirm inserts one row. |
| Payment history | **New section** below the suggestions: `Bob paid Alice $10.00 · recorded by Bob · Tue`. Swipe-to-delete on rows you recorded. |
| Expense detail | The per-split **Settled** marker is removed (decision 4). |
| Notifications | Settlement push fires on insert, addressed to the other party. **Requires an Edge Function change — see below.** |

### `notify-settlement` must change

The function currently sets `fromUserID = callerID` (fix `H-09`: never trust a body-supplied
sender). That assumes the caller is always the payer — which stops being true the moment a
creditor can record. Alice recording "Bob paid Alice" would be announced as *Alice* settling
up, and pushed to Alice herself.

The fix preserves the `H-09` property and is strictly stronger: the function receives a
`settlement_id`, reads that row with the service role, and derives `from_user_id`,
`to_user_id`, `amount` and `currency` from **the row**. It verifies `recorded_by = callerID`,
then pushes to whichever party is not the caller. Nothing security-relevant comes from the
request body at all.

New views go in **their own files**. `GroupDetailView.swift` is already 1,146 lines and was
previously split into three computed properties purely to escape a Swift type-checker timeout;
adding a sheet and a history section to it would make that worse.

## 6. Migration and backfill

`041_settlements.sql` performs, in order:

1. Create table, indexes, RLS policies
2. Backfill one settlement per settled split
3. Leave `splits.is_settled` in place — unread, unwritten, not dropped

```sql
INSERT INTO public.settlements
    (group_id, from_user_id, to_user_id, amount, currency, recorded_by, created_at)
SELECT e.group_id, s.user_id, e.paid_by, s.amount, e.currency, s.user_id,
       COALESCE(s.settled_at, e.created_at)
FROM public.splits s
JOIN public.expenses e ON e.id = s.expense_id
WHERE s.is_settled
  AND e.paid_by IS NOT NULL
  AND e.paid_by <> s.user_id;
```

`recorded_by` is the debtor because, under the RLS in force until now, only the debtor could
have settled it. That is a fact about the old policy, not an assumption.

Expected: 7 rows, all with real `settled_at`, no null payers.

The column is retained for one release so that if the backfill proves wrong, the original
state is still on disk to re-derive from. A later migration drops it.

**Deployment gate.** The migration is written and tested locally first. Per-user balances
before and after are shown to the user. Nothing is applied to the live database without
explicit approval.

## 7. Out of scope

- **IOUs.** `ious.is_settled` is a separate friend-to-friend mechanism with its own service.
  Untouched.
- **Cross-group settling.** The Home "Simplify Debts" list stays display-only, as it is today.
- **Editing a payment.** Delete and re-record.
- **Notes and backdating on a payment.** Not needed yet.
- **Dropping `splits.is_settled`.** A later migration.
- **Two-sided confirmation** (debtor claims / creditor confirms). The ledger records one
  party's assertion, attributed. A confirmation workflow is a separate feature.

## 8. Testing

| Level | Cover |
|---|---|
| Pure | Balance computation from expenses + settlements: exact payment, over-payment reversing direction, mutual netting, payment against no debt, deleted payment restoring the balance |
| View model | With injected fakes: record → balance drops; delete → balance returns; failed insert rolls back and surfaces an error |
| Backfill | Run against seeded data and assert every user's net balance is **identical** before and after. This must be green before anything touches production. |
| Device | Record a payment **as the creditor** — the path that silently failed before — confirm it appears in history, the balance moves, and the other party's push arrives |

## 9. Success criteria

1. A creditor can record a payment they received, and it persists.
2. Every recorded payment shows who recorded it, and its recorder can delete it.
3. Balances after the backfill match balances before it, per user, exactly.
4. `REV-01` closed; `REV-02` and `REV-13` no longer expressible.
5. No code reads `splits.is_settled`.

# Editable expense splits — scope

**Status:** scope only, nothing built. Raised by the owner asking whether an expense can be split
to a member who joined the group after it was created.

## The problem

Splits are written once, by `add_expense_with_splits`, and never touched again. The only two
`splits` operations in the app are `SELECT`. That produces three distinct defects, all silent.

### EXP-01 — a late-joining member cannot be added to an existing expense
The original question. There is no path to change who an expense is split between. The workaround
is to delete and re-create it, which loses the created-at ordering and any comments on it.

### EXP-02 — editing the amount changes no balances
`saveEdit` writes a new `amount` to `expenses` and leaves splits alone. Balances derive from
splits:

```swift
for split in splits[expense.id] ?? [] {
    guard split.userID != payerID else { continue }
    balances[payerID]      += rounded
    balances[split.userID] -= rounded
}
```

Correct a £100 dinner to £120 and the row displays £120 while every balance still reflects £100.
The user watches the correction save successfully and it does nothing.

### EXP-03 — editing "Paid by" corrupts balances in both directions
`payerID` decides whose split is skipped and who is credited. Change it without rewriting splits
and the new payer's own share becomes a debt they owe themselves, while the former payer keeps
none. Two people's balances go wrong at once, in opposite directions, with no warning.

**EXP-02 and EXP-03 are live in production today** — they are reachable from the edit sheet in
1.2, which is approved and live.

## Verified constraints

| Fact | Consequence |
|---|---|
| `splits` has INSERT, DELETE, SELECT and UPDATE policies, all group-member scoped | A plain (non-`SECURITY DEFINER`) RPC suffices; RLS already enforces membership. No policy changes needed. |
| `expenses` has **no `updated_at`** | There is no optimistic-concurrency token. Two people editing the same expense = silent lost update. |
| **The split strategy is not persisted** | `splits` stores amounts only. Nothing records whether the user chose equal, exact, percentage or shares. |

That last one is the design-shaping discovery.

## Design

### One RPC, not three writes
`update_expense_with_splits(p_expense_id, p_title, p_amount, p_currency, p_category, p_notes,
p_paid_by, p_splits split_input[])` — updates the expense row, deletes the existing splits and
inserts the new set, **in one transaction**. Mirrors `add_expense_with_splits`. Anything less
leaves a window where an expense's splits do not sum to it.

### Amount edits scale proportionally
Because the strategy is not stored, a changed amount cannot be re-split "the way the user
originally chose". Re-splitting equally would silently destroy a deliberate 70/30.

**Scale the existing splits by the ratio of new to old total.** That preserves intent for every
strategy uniformly — equal stays equal, 70/30 stays 70/30, shares stay proportional — without
needing to know which was used. Remainder goes to the payer, as elsewhere in `SplitCalculator`.

### Participant edits require an explicit strategy
Adding or removing someone has no proportional answer, so the sheet must ask — the same
equal/exact/percentage/shares control `AddExpenseView` already has. This is mostly reuse:
`SplitCalculator` and the split-input UI exist.

## Decisions needed from the owner

**1. Existing settlements.** Balances are derived, so changing splits retroactively changes what
people owe — including for someone who has already paid. The settlements ledger still offsets
correctly, but a person who settled up may find themselves owed or owing again.
*Recommend:* allow it, with a warning naming how many payments are affected. Blocking is
frustrating; silence is worse.

**2. Members who have left.** `group_members.is_active` distinguishes historical members. An
expense may legitimately be split with someone who has since left.
*Recommend:* preserve their existing split and show it read-only; do not offer them as a new
addition. Silently dropping them would rewrite history.

**3. Notify people added to an expense.** Being added means owing money you did not owe a moment
ago.
*Recommend:* yes, but as a follow-up — it needs an Edge Function change and is not required for
correctness.

**4. Concurrency.** With no `updated_at`, two editors silently overwrite each other, and the loser
is not told.
*Recommend:* add `updated_at` and reject a stale write. Cheap now, and impossible to retrofit
cleanly once people rely on editing.

**5. Recurring expenses.** Editing an instance must not alter the template, and editing a template
must not rewrite instances already generated.
*Recommend:* edit affects only the row in hand. Needs an explicit test either way.

**6. Audit.** Splitwise shows "X updated this expense". Changing what someone owes without a trace
is a trust problem in a shared ledger.
*Recommend:* out of scope, but worth its own decision later.

## Phasing

**Phase 1 — correctness (no new UI).** The RPC, plus proportional rescaling on amount change and a
full split rewrite on payer change. Fixes EXP-02 and EXP-03, which are live defects. Ships without
any new screen.

**Phase 2 — the feature.** Participant selection and strategy control in the edit sheet. Fixes
EXP-01, the original question.

Phase 1 is smaller, is a bug fix rather than a feature, and could ship on its own.

## Risks

- **Money changes under people.** This is the first path in xBill that alters an existing debt.
  Every other write adds a new fact. Warning copy matters more than usual.
- **Rounding.** Rescaled splits must still sum exactly to the new total; the remainder rule must
  match `SplitCalculator` or two code paths will disagree about a penny.
- **`GroupViewModel` state.** Balances must be reapplied in **one** synchronous mutation — the
  settle-up delete crash came from awaiting between two updates feeding the same `List`.
- **The corpus has no equivalent.** Unlike the scanner, there is no benchmark here. Correctness
  rests on unit tests over `SplitCalculator` plus device verification.

## Verification plan

- Unit: proportional rescale preserves ratios and sums exactly, for equal / exact / percentage /
  shares; payer change moves credit correctly; a removed participant's debt disappears.
- Regression: an expense edited to the same values produces byte-identical splits.
- Device: edit an amount and confirm the other member's balance moves — the check EXP-02 would
  have failed.
- Read-only production query confirming no expense has splits that fail to sum to its amount,
  before and after.

## Estimate

Phase 1: one migration, one service method, changes to `saveEdit`, ~8 unit tests.
Phase 2: participant/strategy UI in the edit sheet, largely reusing `AddExpenseView` components.

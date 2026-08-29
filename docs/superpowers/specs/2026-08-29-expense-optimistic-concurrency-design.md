# Expense editing: optimistic concurrency

**Date:** 2026-08-29
**Status:** design approved, not implemented
**Scope:** `expenses.updated_at` / `updated_by`, `update_expense_with_splits`, the expense edit sheet

---

## The defect

Two people editing the same expense silently overwrite each other. Last write wins, no conflict,
no warning, no record. The thing being overwritten is money.

This has been live since migration 043 added `updated_at` on 2026-08-23. That migration's own header
says the column exists "so that optimistic concurrency can be added without a second migration once
editing is in real use" — and nothing has read it since. Verified 2026-08-29: `grep` for
`updatedAt|updated_at` across all Swift returns **zero** hits.

It is the same shape as the `splits.is_settled` defect closed the same week: a column exists, its
purpose is documented, and no code consults it. The difference is that this one loses user data.

---

## What is actually being fixed, in two parts

### 1. The missing precondition

An edit is written unconditionally. Nothing asserts the row still looks the way it did when the
user opened the sheet.

### 2. A second, unguarded write nobody knew was there

Found while designing this. Saving an edit writes to the server **twice**:

```
ExpenseDetailView.saveEdit :501/:531  → updateExpenseWithSplits  → RPC (updates expense + splits)
  → onUpdated?(saved)
    → GroupDetailView :469            → vm.updateExpense(saved)
      → GroupViewModel :702           → ExpenseService.updateExpense  → plain UPDATE expenses
```

Three consequences:

- A wasted round-trip on every edit.
- `ExpenseService.swift:180-183` documents the opposite invariant — *"Every edit now goes through
  here so there is a single write path"*. It does not hold.
- **It would silently defeat this feature.** `updateExpense` does `.update(expense)` on the whole
  struct. The moment `updatedAt` joins `CodingKeys`, that second write serialises the client's
  *stale* token straight back into the row, undoing the guard microseconds after it passed. A
  precondition on the RPC alone would appear to work and be worthless.

`ExpenseService.swift:170` is the **only** server-bound whole-struct `Expense` write in the app
(verified by grep). Deleting it removes the only code path that can write the token.

---

## Decisions

| Question | Decision |
|---|---|
| Conflict UX | **Refuse and reload.** Save rejected, sheet reloads the server version, user re-applies. Nothing merged, nothing invented. |
| Second write | **Delete it.** `onUpdated` updates local state only. |
| Rows with `updated_at IS NULL` | **Backfill to `created_at`**, then `NOT NULL DEFAULT now()`. |
| Where the guard lives | **Inside the RPC**, in the same transaction as the write. |
| How a conflict is signalled | **A distinct SQLSTATE (`XB409`)**, matched exactly — never a message substring. |
| Attribution | **Add `updated_by`**, so the message can name the person. |

### Why refuse-and-reload rather than merge

Merging non-conflicting fields can produce a total nobody authored — one person's amount with
another's splits — which the RPC's own sum invariant would then reject anyway. An expense edit is
small and cheap to redo. The goal is to convert a silent loss into a visible, recoverable event,
which refusal achieves and merging complicates.

### Why the guard belongs in the RPC

A client-side pre-check (`SELECT`, compare, then write) is a **TOCTOU race** — another edit can land
between the check and the write, which is the exact bug being fixed, with extra steps and an
appearance of safety.

A direct table `UPDATE … .eq("updated_at", …)` with an affected-row check would work for the
`expenses` row alone, but the edit must also replace `splits` atomically. Doing that client-side
reintroduces **SPLIT-02**, where an expense displayed a new amount while every balance still
reflected the old one. That trades a solved problem for an unsolved one.

### Why a SQLSTATE and not an error message

The RPC currently raises the same text for a missing row and an RLS refusal. If conflicts join that
bucket, the client can only tell them apart by string-matching. This codebase has been burned by
substring matching three times — `isNotFoundError` matching a bare `"406"`, `credit` matching
`CREDIT CARD PURCHASE`, `table` matching `Vegetable`. PostgREST surfaces SQLSTATE as a structured
`code`, so the client matches it exactly.

---

## Migration 051

Four table statements, **in this order**, followed by the DROP+CREATE of the RPC below.
`SET NOT NULL` fails if the backfill has not run.

```sql
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS updated_by uuid;

UPDATE public.expenses SET updated_at = created_at WHERE updated_at IS NULL;
ALTER TABLE public.expenses ALTER COLUMN updated_at SET DEFAULT now();
ALTER TABLE public.expenses ALTER COLUMN updated_at SET NOT NULL;
```

`updated_by` stays **nullable**: rows that predate this have no author, and inventing one would be
a lie. A null renders as "Someone", which is the truth for those rows.

With `DEFAULT now()`, `add_expense_with_splits` populates `updated_at` on creation for free. No
change to the creation path.

### The RPC must be DROP + CREATE, not CREATE OR REPLACE

`CREATE OR REPLACE FUNCTION` with a *different argument list* does not replace the function — it
creates a second overload. That is defect **H-11** in this repo ("old 7-parameter
`add_expense_with_splits` overload not DROPped after migration 013 — orphaned executable
function"), and PostgREST would then have two candidates. Migration 027 already establishes
DROP+CREATE here.

Two consequences of dropping:

- **Grants die with the function** and must be re-issued.
- **`REVOKE … FROM PUBLIC` does not restrict it on Supabase.** `ALTER DEFAULT PRIVILEGES` grants
  `EXECUTE` to `anon` explicitly at creation, and a `PUBLIC` revoke does not remove an explicit
  grant. Revoke from **`anon` by name**, as migration 044 does. The `REVOKE … FROM PUBLIC` lines in
  042/043 read as protection and are not.

### New signature

One trailing argument, defaulted:

```sql
p_expected_updated_at timestamptz DEFAULT NULL
```

The `UPDATE` becomes conditional, and the conflict is distinguished from the not-found case:

```sql
UPDATE public.expenses
   SET title = p_title, ..., updated_at = now(), updated_by = auth.uid()
 WHERE id = p_expense_id
   AND (p_expected_updated_at IS NULL OR updated_at = p_expected_updated_at)
RETURNING * INTO v_expense;

IF v_expense.id IS NULL THEN
    -- Distinguish "someone else changed it" from "gone or refused". Without this branch a
    -- conflict is indistinguishable from an RLS failure and the client cannot offer a reload.
    IF p_expected_updated_at IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.expenses WHERE id = p_expense_id) THEN
        RAISE EXCEPTION 'This expense was changed by someone else'
            USING ERRCODE = 'XB409';
    END IF;
    RAISE EXCEPTION 'Expense not found, or you do not have permission to edit it';
END IF;
```

The `EXISTS` re-check is inside the same transaction, so it cannot disagree with the `UPDATE`.

### `DEFAULT NULL` is the compatibility hinge

Clients on 1.0–1.5 send 8 keys, resolve to this same function, receive `NULL`, and skip the check.
They keep working untouched — and they remain able to clobber, which cannot be fixed without
breaking them. This is the same adoption asymmetry as `splits.is_settled`: **the guard protects
writes made by updated clients; it cannot protect against writes made by old ones.**

---

## Client changes

### Model

Add to `Expense`:

```swift
/// Opaque concurrency token. A STRING, never a `Date` — see below.
var updatedAt: String?
var updatedBy: UUID?
```

**Optional, even though `updated_at` becomes `NOT NULL`.** `CacheService` caches expenses as JSON,
and entries written before this change carry no such key. A non-optional would fail to decode every
cached expense — the `is_settled` failure in miniature, on our own cache rather than the server.

#### The token must be an opaque string, not a `Date`

`updated_at` is `timestamptz`, which Postgres stores to **microsecond** precision. Swift's `Date` is
a `Double` of seconds, and the project's ISO-8601 encoding does not reliably preserve six fractional
digits — this repo has already hit exactly that, decoding `expires_at`'s six-digit fractional seconds
in `InvitePreviewTests`.

Decoding to `Date` and re-encoding would therefore round the token. The comparison
`updated_at = p_expected_updated_at` would then fail **against a row nobody had touched**, and every
save would report a phantom conflict — a guard that fires constantly is worse than no guard, because
it trains people to distrust it.

So the client treats the token as **opaque**: decode the raw JSON string, send that exact string
back, never parse it. Postgres casts it to `timestamptz` on the way in, so the comparison happens
between two real timestamps and byte-for-byte round-tripping makes precision loss impossible. The
client has no reason to interpret this value — it is a version tag that happens to look like a time.

Display copy uses `updatedBy` for the name and the expense's own fields for the before/after; it
never renders the token.

#### A nil token must not silently disable the guard

`p_expected_updated_at = NULL` means "skip the check". That is correct for old clients, and wrong
for a new client whose `Expense` came from a **pre-upgrade cache entry**, where the key is absent
and `updatedAt` decodes as nil. Left alone, the first edit after upgrading — the one most likely to
race, because the app has just been reopened — would run unguarded.

So: if `updatedAt` is nil when the edit sheet saves, **re-fetch the expense first** and use the
token from the fresh row. The nil branch never reaches the server.

No custom `encode(to:)`. Deleting the write path is stronger than guarding it, and matches what this
repo already does with hazardous methods (`settleSplit`, `fetchInvite` — both deleted, not
commented, so they cannot be reintroduced). Cache encoding keeps the token, which is desirable: a
cached expense retains what it was loaded with.

### Delete the second write path

- `ExpenseService.updateExpense` — delete
- `GroupViewModel.updateExpense` — delete
- `ExpenseDataProviding.updateExpense` — delete the requirement, update fakes (it is on
  `ExpenseDataProviding`, not `GroupDataProviding`, though both live in `GroupDataProviding.swift`)
- Add `GroupViewModel.applySavedExpense(_:)`: replace the row in `expenses`, recompute balances,
  **no network call**
- `GroupDetailView:469` `onUpdated` → `applySavedExpense`

### Service

`updateExpenseWithSplits(_:splits:expectedUpdatedAt:)`. Add `p_expected_updated_at` to
`UpdateExpenseParams`' hand-written `encode(to:)` using `encode`, **never `encodeIfPresent`** — the
key is always present, explicitly null when absent. Omitting a nil key is what made the function
"disappear" with `PGRST202` in SPLIT-04.

### Error handling

Map PostgREST `code == "XB409"` — exact match on the structured code, never a substring of the
message. On conflict, `saveEdit` re-fetches the expense and its splits, refreshes the sheet, and
raises the alert through the `self.error` surface already present in `ExpenseDetailView` (`:493`),
so feedback stays on the pushed screen that produced it rather than flashing on a parent.

Copy, with the editor named from `vm.members` when `updatedBy` is known:

> **Couldn't save**
> Priya changed this expense while you were editing.
> Dinner  $120.00 → $145.00
> Your changes weren't saved. Review theirs and try again.
> `[ Review theirs ]`

When `updatedBy` is null (pre-migration rows), "Priya" becomes "Someone".

---

## Testing

Three pure, unit-testable seams:

| Test | Asserts |
|---|---|
| `UpdateExpenseParams` wire format | `p_expected_updated_at` always present; explicitly null when nil. Extends `UpdateExpensePayloadTests`. |
| Conflict mapping | `XB409` maps to the conflict case; a neighbouring code does not. Exact code, not substring. |
| `applySavedExpense` | Performs **zero fetches**, asserted the way `PaymentRecomputeIsSynchronousTests` already does. |
| Token round-trip | An `updated_at` string with six fractional digits decodes and re-encodes **byte-identically**. This is the test that fails if anyone "tidies" the token into a `Date`. |
| Nil-token guard | A nil `updatedAt` triggers a re-fetch and never sends null to the server. |

Mutation check: removing the `AND (p_expected_updated_at IS NULL OR …)` clause must fail a specific
test rather than none.

Live read-only verification against production, the technique used for migration 043's three
guards: call the RPC with a deliberately stale timestamp and confirm it raises `XB409` **without
writing**. Confirm the row is untouched afterwards.

---

## What this does not do

- **No two-device race is exercised.** The mechanism will be proven; the race will not. Proving it
  needs two accounts editing one expense simultaneously, which no suite here can reach.
- **Old clients (1.0–1.5) can still clobber.** Unavoidable without breaking them.
- **Splits are not independently guarded.** They are replaced wholesale inside the same transaction
  as the expense, so the expense's token covers them.
- **No other write path is touched.** `setNextOccurrenceDate` and `createRecurringInstance` are
  machine writes with a different concurrency story (CRIT-01 territory) and are deliberately out of
  scope.

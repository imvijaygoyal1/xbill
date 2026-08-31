# Expense Optimistic Concurrency Implementation Plan

> ## Status as of 2026-08-31
>
> | Task | State |
> |---|---|
> | 1 — write migration 051 | ✅ done (`28319fa`) |
> | **2 — deploy migration 051** | ⛔ **NOT DONE — held at the owner's direction.** Everything below is inert in production until this lands |
> | 3 — token on the model | ✅ done (`3f44a8b`) |
> | 4 — send the token | ✅ done (`7770eec`) |
> | 5 — map `XB409` | ✅ done (`8b16c23`) |
> | 6 — delete the second write | ✅ done (`f1401d0`) |
> | 7 — conflict handling in the sheet | ✅ code done (`f16a27e`); **Step 4's save check is blocked on Task 2** — 9 keys against the live 8-arg RPC is `PGRST202` |
> | 8 — verification + docs | ✅ docs done; full run 493/493, Release clean |
>
> **Two corrections to this plan, both found by running it:**
> 1. **Task 6's "performs zero fetches" assertion is wrong** and was not implemented. The RPC
>    replaces the splits, so `applySavedExpense` must recompute from re-read splits or SPLIT-02
>    returns. Only the second *write* was ever the problem. See `ApplySavedExpenseTests`.
> 2. **The expected suite totals in this plan are exact** (487 → 490 → 492/493). An earlier claim
>    that they were stale came from counting `grep -c '^Test case'` log lines, which parallel
>    clones duplicate and truncate. Read counts from the `.xcresult`.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop two people editing the same xBill expense from silently overwriting each other.

**Architecture:** A compare-and-swap inside the existing `update_expense_with_splits` RPC. The client sends the `updated_at` value it loaded; the RPC updates only if the row still carries it, and raises SQLSTATE `XB409` otherwise. The redundant second write in the save path is deleted, because it would otherwise write the client's stale token back and undo the guard.

**Tech Stack:** Swift 6 / SwiftUI / `@Observable`, Supabase (PostgREST + plpgsql), Swift Testing (`@Suite`/`@Test`), xcodegen.

**Spec:** `docs/superpowers/specs/2026-08-29-expense-optimistic-concurrency-design.md`

## Global Constraints

- **Run every build and test with the sandbox disabled.** Builds in this environment wedge before compiling a single file otherwise. Recorded in CLAUDE.md (2026-07-15) and re-confirmed 2026-08-28.
- **Test command:** `scripts/run-coverage.sh unit --destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA'` (iPhone 17 Pro, iOS 26.5 — the highest installed runtime).
- **Baseline suite count is 482 passing, 0 failed, 0 skipped.** Every task states the new expected total.
- **Confirm suites by name in the `.xcresult`, never infer from exit code.** `xcrun xcresulttool get test-results tests --path <bundle>`.
- **The concurrency token is an opaque `String`.** Never a `Date`, never parsed, never reformatted. `timestamptz` is microsecond precision and Swift's `Date` is a `Double`; round-tripping rounds it and every save would report a phantom conflict.
- **Every optional in an RPC params struct uses `encode`, never `encodeIfPresent`.** PostgREST resolves an RPC by the exact key set received; an omitted nil key makes the function "disappear" with `PGRST202` (defect SPLIT-04).
- **Never deploy a migration without explicit user approval** (CLAUDE.md standing rule). Task 2 is the only task that touches production and is gated.
- **SQLSTATE for a conflict is exactly `XB409`.** Match on the structured `PostgrestError.code`, never on message text.
- **Run `xcodegen generate` immediately after creating or deleting any `.swift` file, before building.** `project.yml:154` declares `xBillTests` sources as a *directory path* and `xBill.xcodeproj/project.pbxproj` is tracked, so XcodeGen resolves that directory into explicit file references at generation time. A new test file that has not been regenerated into the project **is never compiled** — the suite passes at the old count and you have measured nothing. This plan creates two test files (Tasks 3 and 5) and deletes no source files.
- **A suite count that did not move is a failure, not a pass.** Every task states its expected total. If the count is unchanged after adding tests, the new file is not in the project — run `xcodegen generate` and re-run before reporting anything.
- **After `xcodegen generate`, strip the worktree path out of `project.pbxproj` before committing.** XcodeGen names the group holding `Secrets.xcconfig` after the project's own containing directory. Run inside this worktree that becomes `expense-optimistic-concurrency`; on `main` it must be `xBill`. Committing the worktree spelling breaks `baseConfigurationReference` after merge — Debug silently falls back to placeholder Supabase credentials and Release fails fast by design. **`grep -c "expense-optimistic-concurrency" xBill.xcodeproj/project.pbxproj` must return 0 before every commit.** Keep the new-test-file entries; revert only the `TEMP_*` UUID churn, the group `path`, and the two `baseConfigurationReference` lines. Found in Task 3, review 1.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `supabase/migrations/051_expense_concurrency.sql` | `updated_by` column, `updated_at` backfill + `NOT NULL DEFAULT now()`, DROP+CREATE the RPC with the guard | **Create** |
| `scripts/verify-expense-concurrency.sql` | Read-only post-deploy verification | **Create** |
| `xBill/Models/Expense.swift` | Carries the opaque token and the editor's id | Modify |
| `xBill/Services/ExpenseService.swift` | Sends the token; loses the whole-struct write | Modify |
| `xBill/Services/GroupDataProviding.swift` | Drops the `updateExpense` requirement | Modify |
| `xBill/Core/AppError.swift` | New `.editConflict` case + `XB409` mapping | Modify |
| `xBill/ViewModels/GroupViewModel.swift` | `applySavedExpense` replaces the writing `updateExpense` | Modify |
| `xBill/Views/Groups/GroupDetailView.swift` | Rewires `onUpdated` | Modify |
| `xBill/Views/Expenses/ExpenseDetailView.swift` | Sends token, handles conflict, reloads | Modify |
| `xBillTests/ExpenseTokenTests.swift` | Token decodes and round-trips byte-identically | **Create** |
| `xBillTests/UpdateExpensePayloadTests.swift` | Extended for the 9th key | Modify |
| `xBillTests/EditConflictMappingTests.swift` | `XB409` maps to `.editConflict`, neighbours do not | **Create** |
| `xBillTests/GroupViewModelStateTests.swift` | Fake loses `updateExpense`; `applySavedExpense` does zero fetches | Modify |

---

## Task 1: Write migration 051 (no deploy)

**Files:**
- Create: `supabase/migrations/051_expense_concurrency.sql`
- Create: `scripts/verify-expense-concurrency.sql`

**Interfaces:**
- Consumes: nothing.
- Produces: `public.update_expense_with_splits(p_expense_id uuid, p_title text, p_amount numeric, p_currency text, p_category text, p_notes text DEFAULT NULL, p_paid_by uuid DEFAULT NULL, p_splits public.split_input[] DEFAULT NULL, p_expected_updated_at timestamptz DEFAULT NULL) RETURNS public.expenses`. Raises SQLSTATE `XB409` on conflict. Also `public.expenses.updated_by uuid` (nullable) and `public.expenses.updated_at timestamptz NOT NULL DEFAULT now()`.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/051_expense_concurrency.sql`:

```sql
-- 051_expense_concurrency.sql
--
-- Two people editing the same expense silently overwrite each other. Last write wins, no
-- conflict, no warning, and the thing being overwritten is money. Live since 043 added
-- `updated_at` on 2026-08-23 and nothing ever read it.
--
-- See docs/superpowers/specs/2026-08-29-expense-optimistic-concurrency-design.md

-- Who last changed the row, so the conflict message can name them. Nullable on purpose: rows
-- that predate this migration have no author and inventing one would be a lie. A null renders
-- as "Someone".
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS updated_by uuid;

-- Order is load-bearing. SET NOT NULL fails if the backfill has not run. `created_at` is a
-- truthful "last known change" for a row that has never been edited.
UPDATE public.expenses SET updated_at = created_at WHERE updated_at IS NULL;
ALTER TABLE public.expenses ALTER COLUMN updated_at SET DEFAULT now();
ALTER TABLE public.expenses ALTER COLUMN updated_at SET NOT NULL;

-- DROP + CREATE, never CREATE OR REPLACE.
--
-- CREATE OR REPLACE with a DIFFERENT argument list does not replace the function -- it creates a
-- second overload, and PostgREST is then left with two candidates. That is defect H-11 in this
-- repository: the old 7-parameter `add_expense_with_splits` was left executable after migration
-- 013 for exactly this reason.
DROP FUNCTION IF EXISTS public.update_expense_with_splits(
    uuid, text, numeric, text, text, text, uuid, public.split_input[]);

CREATE FUNCTION public.update_expense_with_splits(
    p_expense_id          uuid,
    p_title               text,
    p_amount              numeric,
    p_currency            text,
    p_category            text,
    p_notes               text                  DEFAULT NULL,
    p_paid_by             uuid                  DEFAULT NULL,
    p_splits              public.split_input[]  DEFAULT NULL,
    -- The compatibility hinge. Clients on 1.0-1.5 send 8 keys, resolve to this same function,
    -- receive NULL here, and skip the check -- they keep working untouched. They also remain
    -- able to clobber, which cannot be fixed without breaking them.
    p_expected_updated_at timestamptz           DEFAULT NULL
)
RETURNS public.expenses
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_expense public.expenses%ROWTYPE;
    v_sum     numeric;
BEGIN
    IF p_splits IS NULL OR array_length(p_splits, 1) IS NULL THEN
        RAISE EXCEPTION 'An expense must have at least one split';
    END IF;

    SELECT coalesce(sum(s.amount), 0) INTO v_sum FROM unnest(p_splits) AS s;
    IF round(v_sum, 2) <> round(p_amount, 2) THEN
        RAISE EXCEPTION 'Splits sum to % but the expense is %', v_sum, p_amount;
    END IF;

    UPDATE public.expenses
       SET title      = p_title,
           amount     = p_amount,
           currency   = p_currency,
           category   = p_category,
           notes      = p_notes,
           paid_by    = p_paid_by,
           updated_at = now(),
           updated_by = auth.uid()
     WHERE id = p_expense_id
       AND (p_expected_updated_at IS NULL OR updated_at = p_expected_updated_at)
    RETURNING * INTO v_expense;

    IF v_expense.id IS NULL THEN
        -- Distinguish "someone else changed it" from "gone, or RLS refused it". Without this
        -- branch a conflict is indistinguishable from a permission failure and the client cannot
        -- offer a reload. The EXISTS runs in the same transaction as the UPDATE, so the two
        -- cannot disagree.
        IF p_expected_updated_at IS NOT NULL
           AND EXISTS (SELECT 1 FROM public.expenses WHERE id = p_expense_id) THEN
            RAISE EXCEPTION 'This expense was changed by someone else'
                USING ERRCODE = 'XB409';
        END IF;
        RAISE EXCEPTION 'Expense not found, or you do not have permission to edit it';
    END IF;

    DELETE FROM public.splits WHERE expense_id = p_expense_id;

    INSERT INTO public.splits (expense_id, user_id, amount)
    SELECT p_expense_id, s.user_id, s.amount FROM unnest(p_splits) AS s;

    RETURN v_expense;
END;
$$;

-- Grants die with the dropped function and must be re-issued.
--
-- REVOKE ... FROM PUBLIC does NOT restrict anything on Supabase: ALTER DEFAULT PRIVILEGES grants
-- EXECUTE to `anon` explicitly at creation, and revoking from PUBLIC does not remove an explicit
-- grant. `anon` must be named. The REVOKE ... FROM PUBLIC lines in 042 and 043 read as protection
-- and are not.
REVOKE ALL ON FUNCTION public.update_expense_with_splits(
    uuid, text, numeric, text, text, text, uuid, public.split_input[], timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_expense_with_splits(
    uuid, text, numeric, text, text, text, uuid, public.split_input[], timestamptz) FROM anon;
GRANT  EXECUTE ON FUNCTION public.update_expense_with_splits(
    uuid, text, numeric, text, text, text, uuid, public.split_input[], timestamptz) TO authenticated;

COMMENT ON COLUMN public.expenses.updated_at IS
    'Optimistic-concurrency token. Clients send the value they loaded as p_expected_updated_at; '
    'update_expense_with_splits refuses the write if it no longer matches (SQLSTATE XB409).';
COMMENT ON COLUMN public.expenses.updated_by IS
    'Who last edited the row, so a conflict can name them. Nullable: rows predating migration 051 '
    'have no recorded author.';
```

- [ ] **Step 2: Write the read-only verification script**

Create `scripts/verify-expense-concurrency.sql`. Run this AFTER deploy. It writes nothing.

```sql
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
```

- [ ] **Step 3: Verify the constraint and column names referenced actually exist**

Run: `grep -n "updated_at" supabase/migrations/043_update_expense_with_splits.sql`
Expected: line 19 shows `ADD COLUMN IF NOT EXISTS updated_at timestamptz;`

Run: `grep -c "split_input" supabase/migrations/002_rpc_add_expense.sql`
Expected: non-zero — the composite type the signature depends on exists.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/051_expense_concurrency.sql scripts/verify-expense-concurrency.sql
git commit -m "Migration 051: optimistic concurrency guard for expense edits (not deployed)"
```

---

## Task 2: Deploy migration 051 — GATED

**Files:** none changed.

**Interfaces:**
- Consumes: Task 1's migration file.
- Produces: the live 9-argument RPC.

> **STOP. This task writes to production.** It backfills `updated_at` on every expense row and
> replaces a live function. CLAUDE.md forbids deploying a migration without explicit approval.
> Ask the user, in these words: *"Migration 051 is ready. It backfills `updated_at = created_at`
> on roughly 46 expense rows and replaces `update_expense_with_splits`. Deploy to production?"*
> Do not proceed without a yes.

> **Ordering hazard:** the server must accept 9 keys **before** any client sends them. A client
> built with Task 4's change, run against a pre-051 database, gets `PGRST202` and expense editing
> dies. Deploy before exercising the app against production.

- [ ] **Step 1: Preflight — count rows that will be written**

Run in the Supabase SQL editor (read-only):

```sql
SELECT count(*) AS rows_to_backfill FROM public.expenses WHERE updated_at IS NULL;
```

Record the number. It is the exact number of rows the deploy will modify.

- [ ] **Step 2: Deploy**

Run: `supabase db push --linked`
Expected: `Applying migration 051_expense_concurrency.sql...` then `Finished supabase db push.`

- [ ] **Step 3: Confirm local matches remote**

Run: `supabase migration list --linked | tail -4`
Expected: a row reading `051 | 051 | 051`.

- [ ] **Step 4: Run the verification script**

Run `scripts/verify-expense-concurrency.sql` in the SQL editor.
Expected: `null_tokens = 0`; `is_nullable = NO` and `column_default = now()`; `overloads = 1`;
`anon_exec = false` and `auth_exec = true`.

**If `overloads = 2`, stop.** The DROP did not take and an orphaned 8-argument function is
executable. Drop it explicitly before continuing.

- [ ] **Step 5: Prove the guard fires, without writing**

In the SQL editor, as an authenticated role, call the RPC with a deliberately stale token:

```sql
SELECT public.update_expense_with_splits(
    '<a real expense id>'::uuid, 'x', 1.00, 'USD', 'food', NULL, NULL,
    ARRAY[ROW('<a real user id>'::uuid, 1.00)]::public.split_input[],
    '1999-01-01T00:00:00Z'::timestamptz);
```

Expected: it raises `This expense was changed by someone else` with SQLSTATE `XB409`.
Then confirm nothing moved:

```sql
SELECT title, amount, updated_at FROM public.expenses WHERE id = '<the same id>';
```

Expected: unchanged from before the call.

- [ ] **Step 6: Record the deployment**

Add to `CLAUDE.md` under "Deployed Edge Functions (production)":

```markdown
- Migration 051 ✅ — pushed to production DB (2026-08-29). `updated_by` column; `updated_at` backfilled to `created_at` and made `NOT NULL DEFAULT now()`; `update_expense_with_splits` gains `p_expected_updated_at` and raises SQLSTATE `XB409` on conflict. `migration list --linked` reads `051 | 051 | 051`; guard verified against production without writing.
```

```bash
git add CLAUDE.md
git commit -m "Record migration 051 deployment"
```

---

## Task 3: Carry the token on the Expense model

**Files:**
- Modify: `xBill/Models/Expense.swift`
- Test: `xBillTests/ExpenseTokenTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `Expense.updatedAt: String?` and `Expense.updatedBy: UUID?`, both defaulted to `nil` in the memberwise initialiser so no existing construction site breaks.

- [ ] **Step 1: Write the failing test**

Create `xBillTests/ExpenseTokenTests.swift`:

```swift
//
//  ExpenseTokenTests.swift
//  xBillTests
//
//  `expenses.updated_at` is the optimistic-concurrency token. It is `timestamptz`, which Postgres
//  stores to MICROSECOND precision, and Swift's `Date` is a `Double` of seconds. Decoding to a
//  `Date` and re-encoding rounds the value, so `updated_at = p_expected_updated_at` would fail
//  against a row nobody had touched and every save would report a phantom conflict.
//
//  A guard that fires constantly is worse than no guard: it teaches people to ignore it.
//
//  So the token is opaque. These tests fail if anyone "tidies" it into a `Date`.
//

import Testing
import Foundation
@testable import xBill

@Suite("Expense concurrency token")
struct ExpenseTokenTests {

    private static let json = """
    {"id":"11111111-1111-1111-1111-111111111111",
     "group_id":"22222222-2222-2222-2222-222222222222",
     "title":"Dinner","amount":42.50,"currency":"USD","paid_by":null,
     "category":"food","notes":null,"receipt_url":null,
     "original_amount":null,"original_currency":null,
     "recurrence":"none","next_occurrence_date":null,
     "created_at":"2026-08-29T14:03:11.123456+00:00",
     "updated_at":"2026-08-29T14:03:11.123456+00:00",
     "updated_by":"33333333-3333-3333-3333-333333333333"}
    """

    @Test("Six fractional digits survive decoding byte-identically")
    func tokenKeepsMicroseconds() throws {
        let expense = try SupabaseManager.postgrestDecoder.decode(
            Expense.self, from: Data(Self.json.utf8))
        #expect(expense.updatedAt == "2026-08-29T14:03:11.123456+00:00")
    }

    @Test("The editor's id is decoded")
    func editorIsDecoded() throws {
        let expense = try SupabaseManager.postgrestDecoder.decode(
            Expense.self, from: Data(Self.json.utf8))
        #expect(expense.updatedBy == UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
    }

    /// `CacheService` caches expenses as JSON. Entries written before this change carry no
    /// `updated_at` key at all. A non-optional would fail to decode every one of them — the
    /// `splits.is_settled` failure in miniature, on our own cache instead of the server.
    @Test("A cached expense with no token still decodes")
    func absentTokenDecodesAsNil() throws {
        let legacy = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "group_id":"22222222-2222-2222-2222-222222222222",
         "title":"Dinner","amount":42.50,"currency":"USD","paid_by":null,
         "category":"food","notes":null,"receipt_url":null,
         "original_amount":null,"original_currency":null,
         "recurrence":"none","next_occurrence_date":null,
         "created_at":"2026-08-29T14:03:11.123456+00:00"}
        """
        let expense = try SupabaseManager.postgrestDecoder.decode(
            Expense.self, from: Data(legacy.utf8))
        #expect(expense.updatedAt == nil)
        #expect(expense.updatedBy == nil)
    }
}
```

- [ ] **Step 2: Regenerate the project, then run it and watch it fail**

The file will not compile at all until it is in the project. Run first:

```bash
xcodegen generate
```

Then: `scripts/run-coverage.sh unit --destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA'`
Expected: **compile failure** — `Expense` has no member `updatedAt`.

If instead the suite passes at 482, the new file is not in the project: `xcodegen generate` did not run or did not pick it up. Fix that before continuing — a green run here means the test never executed.

- [ ] **Step 3: Add the properties**

In `xBill/Models/Expense.swift`, add **after** `let createdAt: Date` (declaration order puts them
last in the memberwise initialiser, so every existing `Expense(...)` call site keeps compiling):

```swift
    /// Optimistic-concurrency token, sent back as `p_expected_updated_at`.
    ///
    /// **A `String`, deliberately — never a `Date`.** `timestamptz` is microsecond precision and
    /// `Date` is a `Double`; decoding and re-encoding rounds the value, and the server comparison
    /// would then fail against a row nobody had touched. The client has no reason to interpret
    /// this: it is a version tag that happens to look like a time. See `ExpenseTokenTests`.
    ///
    /// Optional because `CacheService` holds entries written before this key existed.
    var updatedAt: String? = nil

    /// Who last edited the row, so a conflict can name them. Nil for rows predating migration 051.
    var updatedBy: UUID? = nil
```

And add to `CodingKeys`, after `case createdAt`:

```swift
        case updatedAt            = "updated_at"
        case updatedBy            = "updated_by"
```

- [ ] **Step 4: Run the tests**

Run: `scripts/run-coverage.sh unit --destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA'`
Expected: **485 passed, 0 failed, 0 skipped** (482 baseline + 3 new).

Confirm the new suite ran by name:
```bash
xcrun xcresulttool get test-results tests --path TestResults/Coverage/<newest>.xcresult | grep -c "Expense concurrency token"
```
Expected: non-zero.

- [ ] **Step 5: Commit**

```bash
git add xBill/Models/Expense.swift xBillTests/ExpenseTokenTests.swift
git commit -m "Expense carries an opaque concurrency token"
```

---

## Task 4: Send the token with the edit

**Files:**
- Modify: `xBill/Services/ExpenseService.swift` (`UpdateExpenseParams`, `makeUpdateParams`, `updateExpenseWithSplits`)
- Test: `xBillTests/UpdateExpensePayloadTests.swift`

**Interfaces:**
- Consumes: `Expense.updatedAt` from Task 3.
- Produces: `ExpenseService.updateExpenseWithSplits(_ expense: Expense, splits: [SplitInput], expectedUpdatedAt: String?) async throws -> Expense`, and `UpdateExpenseParams.expectedUpdatedAt: String?` encoded as `p_expected_updated_at`.

- [ ] **Step 1: Write the failing tests**

Append to `xBillTests/UpdateExpensePayloadTests.swift`, inside `struct UpdateExpensePayloadTests`:

```swift
    /// PostgREST resolves an RPC by the exact key set it receives, so this key must be present
    /// even when there is no token — exactly the rule `p_notes` taught us in SPLIT-04.
    @Test("The token key is always present, explicitly null when absent")
    func tokenKeyIsAlwaysSent() throws {
        let json = try ExpenseService.updateParamsJSON(
            expense(notes: nil, payer: nil), splits: [input("42.50")],
            expectedUpdatedAt: nil)
        #expect(json.keys.contains("p_expected_updated_at"))
        #expect(json["p_expected_updated_at"] is NSNull)
    }

    @Test("A token is sent verbatim, with its microseconds intact")
    func tokenIsSentVerbatim() throws {
        let token = "2026-08-29T14:03:11.123456+00:00"
        let json = try ExpenseService.updateParamsJSON(
            expense(notes: nil, payer: nil), splits: [input("42.50")],
            expectedUpdatedAt: token)
        #expect(json["p_expected_updated_at"] as? String == token)
    }
```

Also extend the existing required-keys list in the same file:

```swift
    private static let required = ["p_expense_id", "p_title", "p_amount", "p_currency",
                                   "p_category", "p_notes", "p_paid_by", "p_splits",
                                   "p_expected_updated_at"]
```

- [ ] **Step 2: Run and watch it fail**

Run: `scripts/run-coverage.sh unit --destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA'`
Expected: compile failure — `updateParamsJSON` takes no `expectedUpdatedAt` argument.

- [ ] **Step 3: Add the field, the key, and the encoding**

In `xBill/Services/ExpenseService.swift`, add to `UpdateExpenseParams`:

```swift
    let expectedUpdatedAt: String?
```

to `CodingKeys`:

```swift
        case expectedUpdatedAt = "p_expected_updated_at"
```

and to `encode(to:)`, as the last line before the closing brace:

```swift
        try c.encode(expectedUpdatedAt, forKey: .expectedUpdatedAt)  // explicit null, never omitted
```

- [ ] **Step 4: Thread it through the three call sites in ExpenseService**

Replace `makeUpdateParams`, `updateParamsJSON` and `updateExpenseWithSplits` signatures:

```swift
    nonisolated static func makeUpdateParams(_ expense: Expense, splits: [SplitInput],
                                             expectedUpdatedAt: String?) -> UpdateExpenseParams {
        UpdateExpenseParams(
            expenseID: expense.id,
            title:     expense.title,
            amount:    expense.amount,
            currency:  expense.currency,
            category:  expense.category.rawValue,
            notes:     expense.notes,
            paidBy:    expense.payerID,
            splits:    splits.map { RPCSplitParam(userID: $0.userID, amount: $0.amount) },
            expectedUpdatedAt: expectedUpdatedAt
        )
    }

    nonisolated static func updateParamsJSON(_ expense: Expense, splits: [SplitInput],
                                             expectedUpdatedAt: String?) throws -> [String: Any] {
        let data = try SupabaseManager.postgrestEncoder.encode(
            makeUpdateParams(expense, splits: splits, expectedUpdatedAt: expectedUpdatedAt))
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func updateExpenseWithSplits(_ expense: Expense, splits: [SplitInput],
                                 expectedUpdatedAt: String?) async throws -> Expense {
        let params = Self.makeUpdateParams(expense, splits: splits,
                                           expectedUpdatedAt: expectedUpdatedAt)
        return try await supabase.client
            .rpc("update_expense_with_splits", params: params)
            .execute()
            .value
    }
```

Note: `makeUpdateParams` and `updateParamsJSON` keep their exact positional/label shape apart from
the new trailing argument, so the only callers needing change are in `ExpenseDetailView` (Task 7)
and the existing tests updated in Step 1.

- [ ] **Step 5: Fix the two existing call sites in ExpenseDetailView so the project compiles**

In `xBill/Views/Expenses/ExpenseDetailView.swift`, at both `:501` and `:531`, add the argument.
Task 7 replaces this with the real logic; for now pass the loaded value so the project builds:

```swift
expectedUpdatedAt: expense.updatedAt
```

- [ ] **Step 6: Run the tests**

Run: `scripts/run-coverage.sh unit --destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA'`
Expected: **487 passed, 0 failed, 0 skipped** (485 + 2 new).

- [ ] **Step 7: Commit**

```bash
git add xBill/Services/ExpenseService.swift xBill/Views/Expenses/ExpenseDetailView.swift xBillTests/UpdateExpensePayloadTests.swift
git commit -m "Send the concurrency token with an expense edit"
```

---

## Task 5: Map SQLSTATE XB409 to a conflict error

**Files:**
- Modify: `xBill/Core/AppError.swift`
- Test: `xBillTests/EditConflictMappingTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `AppError.editConflict` and `AppError.isEditConflict(_ error: Error) -> Bool`.

- [ ] **Step 1: Write the failing test**

Create `xBillTests/EditConflictMappingTests.swift`:

```swift
//
//  EditConflictMappingTests.swift
//  xBillTests
//
//  The RPC raises the SAME text for a missing row and an RLS refusal. If a concurrency conflict
//  joined that bucket the client could only tell them apart by string-matching an error message.
//
//  This codebase has been burned by substring matching three times: `isNotFoundError` matched a
//  bare "406", the receipt parser's `credit` matched "CREDIT CARD PURCHASE", and `table` matched
//  "Vegetable". So a conflict carries its own SQLSTATE and is matched exactly.
//

import Testing
import Foundation
import Supabase
@testable import xBill

@Suite("Edit-conflict error mapping")
struct EditConflictMappingTests {

    private func pgError(code: String) -> PostgrestError {
        PostgrestError(detail: nil, hint: nil, code: code,
                       message: "This expense was changed by someone else")
    }

    @Test("XB409 is recognised as an edit conflict")
    func exactCodeMatches() {
        #expect(AppError.isEditConflict(pgError(code: "XB409")))
    }

    /// The whole point of a structured code: a neighbouring one must NOT match.
    @Test("A different code is not a conflict")
    func neighbouringCodeDoesNotMatch() {
        #expect(!AppError.isEditConflict(pgError(code: "XB410")))
        #expect(!AppError.isEditConflict(pgError(code: "PGRST202")))
        #expect(!AppError.isEditConflict(pgError(code: "42501")))
    }

    /// Matching must be on the code, never the message — otherwise any error whose text happens
    /// to contain these words becomes a conflict.
    @Test("The message alone does not make a conflict")
    func messageAloneIsNotAConflict() {
        struct Plain: Error, LocalizedError {
            var errorDescription: String? { "This expense was changed by someone else" }
        }
        #expect(!AppError.isEditConflict(Plain()))
    }
}
```

- [ ] **Step 2: Regenerate the project, then run and watch it fail**

This task creates a new test file, so the project must be regenerated or it will never compile:

```bash
xcodegen generate
```

Then: `scripts/run-coverage.sh unit --destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA'`
Expected: **compile failure** — no member `isEditConflict`.

If the suite instead passes at 487, the new file is not in the project. A green run here means the test never executed.

- [ ] **Step 3: Implement it**

In `xBill/Core/AppError.swift`, add `import Supabase` beneath `import Foundation`, add the case
alongside the others:

```swift
    case editConflict
```

give it a description in the existing `errorDescription` switch:

```swift
        case .editConflict:
            return "This expense was changed by someone else"
```

and add the matcher next to `isSilent`:

```swift
    /// SQLSTATE raised by `update_expense_with_splits` when the row moved under the editor.
    ///
    /// Matched on the structured `code`, never on message text — see `EditConflictMappingTests`.
    static let editConflictCode = "XB409"

    static func isEditConflict(_ error: Error) -> Bool {
        guard let pg = error as? PostgrestError else { return false }
        return pg.code == editConflictCode
    }
```

- [ ] **Step 4: Run the tests**

Run: `scripts/run-coverage.sh unit --destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA'`
Expected: **490 passed, 0 failed, 0 skipped** (487 + 3 new).

- [ ] **Step 5: Mutation-test the matcher**

Temporarily change `isEditConflict` to `return true`. Re-run.
Expected: `neighbouringCodeDoesNotMatch` and `messageAloneIsNotAConflict` **fail**;
`exactCodeMatches` still passes. Revert.

A matcher that cannot reject is not a matcher. If all three still pass, the tests are wrong.

- [ ] **Step 6: Commit**

```bash
git add xBill/Core/AppError.swift xBillTests/EditConflictMappingTests.swift
git commit -m "Map SQLSTATE XB409 to an edit-conflict error"
```

---

## Task 6: Delete the second write path

**Files:**
- Modify: `xBill/Services/ExpenseService.swift` (delete `updateExpense`)
- Modify: `xBill/Services/GroupDataProviding.swift` (drop the requirement from `ExpenseDataProviding`)
- Modify: `xBill/ViewModels/GroupViewModel.swift` (replace `updateExpense` with `applySavedExpense`)
- Modify: `xBill/Views/Groups/GroupDetailView.swift:469`
- Test: `xBillTests/GroupViewModelStateTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `GroupViewModel.applySavedExpense(_ saved: Expense) async` — replaces the row in `expenses` and recomputes balances, with **no network call**. `ExpenseService.updateExpense` and `ExpenseDataProviding.updateExpense` cease to exist.

> **Why deletion and not a guard.** `updateExpense` does `.update(expense)` on the whole struct, so
> it writes `updated_at` from the client — a stale token straight back into the row, undoing the
> guard microseconds after it passed. `ExpenseService.swift:170` is the only server-bound
> whole-struct `Expense` write in the app, so deleting it removes the only path that can do this.
> This repo already handles hazardous methods by deleting them (`settleSplit`, `fetchInvite`) so
> they cannot be reintroduced.

- [ ] **Step 1: Write the failing test**

In `xBillTests/GroupViewModelStateTests.swift`, add to the `FakeExpenseService` class a counter:

```swift
    private(set) var fetchCallCount = 0
```

and increment it at the top of both `fetchExpenses` and `fetchSplits`. Then add a new suite at the
end of the file:

```swift
/// Applying a saved expense must not hit the network. The edit has ALREADY been written by
/// `update_expense_with_splits`; a second write was both a wasted round-trip and — once the
/// concurrency token existed — a way to put a stale token back into the row.
///
/// Mirrors `PaymentRecomputeIsSynchronousTests`, which asserts a fetch count for the same reason.
@Suite("Applying a saved expense")
@MainActor
struct ApplySavedExpenseTests {

    @Test("Replaces the row in place and performs zero fetches")
    func appliesWithoutNetwork() async {
        let group = BillGroup(id: UUID(), name: "Trip", emoji: "🏖️", currency: "USD",
                              createdBy: UUID(), isArchived: false, createdAt: Date())
        let fake = FakeExpenseService()
        let vm = GroupViewModel(group: group, expenseService: fake)

        let original = Expense(id: UUID(), groupID: group.id, title: "Dinner",
                               amount: Decimal(string: "100.00")!, currency: "USD",
                               payerID: UUID(), category: .food, notes: nil, receiptURL: nil,
                               originalAmount: nil, originalCurrency: nil, recurrence: .none,
                               nextOccurrenceDate: nil, createdAt: Date())
        vm.expenses = [original]

        var saved = original
        saved.title  = "Dinner (team)"
        saved.amount = Decimal(string: "120.00")!

        let before = fake.fetchCallCount
        await vm.applySavedExpense(saved)

        #expect(fake.fetchCallCount == before)
        #expect(vm.expenses.count == 1)
        #expect(vm.expenses[0].title == "Dinner (team)")
        #expect(vm.expenses[0].amount == Decimal(string: "120.00")!)
    }

    @Test("An unknown expense is ignored rather than appended")
    func unknownExpenseIsIgnored() async {
        let group = BillGroup(id: UUID(), name: "Trip", emoji: "🏖️", currency: "USD",
                              createdBy: UUID(), isArchived: false, createdAt: Date())
        let vm = GroupViewModel(group: group, expenseService: FakeExpenseService())
        vm.expenses = []

        let stranger = Expense(id: UUID(), groupID: group.id, title: "Ghost",
                               amount: Decimal(string: "1.00")!, currency: "USD",
                               payerID: UUID(), category: .food, notes: nil, receiptURL: nil,
                               originalAmount: nil, originalCurrency: nil, recurrence: .none,
                               nextOccurrenceDate: nil, createdAt: Date())
        await vm.applySavedExpense(stranger)

        #expect(vm.expenses.isEmpty)
    }
}
```

> Check `GroupViewModel`'s initialiser label for the injected service before writing this — if it
> differs from `expenseService:`, use the real one. Read `GroupViewModel.init` first.

- [ ] **Step 2: Run and watch it fail**

Run: `scripts/run-coverage.sh unit --destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA'`
Expected: compile failure — no member `applySavedExpense`.

- [ ] **Step 3: Add `applySavedExpense` and delete `updateExpense`**

In `xBill/ViewModels/GroupViewModel.swift`, replace the whole `updateExpense(_:)` method
(currently at `:698`–`:711`) with:

```swift
    /// Applies an expense that has ALREADY been saved by `update_expense_with_splits`.
    ///
    /// Deliberately performs no network call. This used to be `updateExpense`, which wrote the
    /// row a second time: a wasted round-trip that also put the client's stale `updated_at` back
    /// into the row, undoing the concurrency guard. See `ApplySavedExpenseTests`.
    func applySavedExpense(_ saved: Expense) async {
        guard let i = expenses.firstIndex(where: { $0.id == saved.id }) else { return }
        expenses[i] = saved
        await computeBalances()
    }
```

- [ ] **Step 4: Delete the service method and the protocol requirement**

In `xBill/Services/ExpenseService.swift`, delete the whole `updateExpense(_:)` method
(`:168`–`:176`) **and** the `// MARK: - Update` comment directly above it if nothing else follows
it.

In `xBill/Services/GroupDataProviding.swift`, delete this line from `ExpenseDataProviding`:

```swift
    func updateExpense(_ expense: Expense) async throws -> Expense
```

In `xBillTests/GroupViewModelStateTests.swift`, delete the fake's line 43:

```swift
    func updateExpense(_ expense: Expense) async throws -> Expense { expense }
```

- [ ] **Step 5: Rewire the caller**

In `xBill/Views/Groups/GroupDetailView.swift:469`, change:

```swift
onUpdated: { updated in Task { await vm.updateExpense(updated) } },
```

to:

```swift
onUpdated: { updated in Task { await vm.applySavedExpense(updated) } },
```

- [ ] **Step 6: Prove no caller survives**

Run: `grep -rn "updateExpense(" --include="*.swift" xBill/ xBillTests/`
Expected: **no matches**. Any hit is a caller that must be rewired, not left.

- [ ] **Step 7: Run the tests**

Run: `scripts/run-coverage.sh unit --destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA'`
Expected: **492 passed, 0 failed, 0 skipped** (490 + 2 new).

- [ ] **Step 8: Commit**

```bash
git add xBill/Services/ExpenseService.swift xBill/Services/GroupDataProviding.swift xBill/ViewModels/GroupViewModel.swift xBill/Views/Groups/GroupDetailView.swift xBillTests/GroupViewModelStateTests.swift
git commit -m "Delete the redundant second write on expense save"
```

---

## Task 7: Conflict handling in the edit sheet

**Files:**
- Modify: `xBill/Views/Expenses/ExpenseDetailView.swift` (`saveEdit`, both RPC call sites)

**Interfaces:**
- Consumes: `AppError.isEditConflict`, `ExpenseService.updateExpenseWithSplits(_:splits:expectedUpdatedAt:)`, `ExpenseService.fetchExpense(id:)`, `ExpenseService.fetchSplits(expenseID:)`.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add the token resolver**

Add to `ExpenseDetailView`, near `saveEdit`:

```swift
    /// The token to send as `p_expected_updated_at`.
    ///
    /// A nil token means "skip the check" on the server. That is correct for clients on 1.0–1.5,
    /// and WRONG here: a nil can also come from a `CacheService` entry written before the column
    /// existed, and that first edit after upgrading — right when the app has just reopened — is
    /// exactly the one most likely to race. So a nil forces a re-read instead of reaching the
    /// server as "no check".
    private func currentToken() async throws -> String? {
        if let token = expense.updatedAt { return token }
        return try await ExpenseService.shared.fetchExpense(id: expense.id).updatedAt
    }
```

- [ ] **Step 2: Add the conflict reload**

Add alongside it:

```swift
    /// Refuse-and-reload. Nothing is merged and nothing is invented: the user sees the current
    /// server state and re-applies their edit if they still want it.
    ///
    /// Presented through this view's own `error` surface, because feedback for a pushed screen
    /// has to be reachable from that screen — an alert raised on the parent is invisible or
    /// flashes and dies.
    private func handleEditConflict() async {
        isEditing = false
        do {
            let fresh = try await ExpenseService.shared.fetchExpense(id: expense.id)
            let freshSplits = try await ExpenseService.shared.fetchSplits(expenseID: expense.id)
            splits = freshSplits
            onUpdated?(fresh)

            let who = fresh.updatedBy.flatMap { id in
                members.first(where: { $0.id == id })?.displayName
            } ?? "Someone"
            error = .validationFailed(
                "\(who) changed this expense while you were editing. "
                + "It is now \(fresh.title), \(fresh.amount.formatted(currencyCode: fresh.currency)). "
                + "Your changes weren't saved — review theirs and try again.")
        } catch {
            self.error = AppError.from(error)
        }
    }
```

> Check the property that holds group members in this view before writing this — the plan assumes
> `members`. If it is named differently, use the real name. Read the view's stored properties first.

- [ ] **Step 3: Wire both save paths**

At `:501` (the splits-edited branch), replace the call with:

```swift
                let token = try await currentToken()
                let saved: Expense
                do {
                    saved = try await ExpenseService.shared.updateExpenseWithSplits(
                        updated, splits: chosen, expectedUpdatedAt: token)
                } catch where AppError.isEditConflict(error) {
                    await handleEditConflict()
                    return
                }
```

At the second call site (`:531`, the rescaled branch), apply the identical pattern with `inputs`
in place of `chosen`.

- [ ] **Step 4: Build and install**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme xBill \
  -destination 'id=CA2078AC-6559-4BF3-93CB-370CF27E92EA' -configuration Debug build
```
Expected: `** BUILD SUCCEEDED **`

Then install and launch on `CA2078AC-6559-4BF3-93CB-370CF27E92EA`, open an expense, edit the
amount, and confirm it saves normally. This proves the happy path still works; it does **not**
prove the conflict path, which needs two accounts.

- [ ] **Step 5: Run the tests**

Run: `scripts/run-coverage.sh unit --destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA'`
Expected: **492 passed, 0 failed, 0 skipped** — unchanged. This task adds view code, which this
suite cannot reach.

- [ ] **Step 6: Commit**

```bash
git add xBill/Views/Expenses/ExpenseDetailView.swift
git commit -m "Refuse and reload when an expense changed underneath the editor"
```

---

## Task 8: Verification and documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `AUDIT_REPORT.md`

**Interfaces:** none.

- [ ] **Step 1: Full unit run**

Run: `scripts/run-coverage.sh unit --destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA'`
Expected: **492 passed, 0 failed, 0 skipped**.

Confirm all three new suites by name:
```bash
xcrun xcresulttool get test-results tests --path TestResults/Coverage/<newest>.xcresult \
  | grep -oE "Expense concurrency token|Edit-conflict error mapping|Applying a saved expense" | sort -u
```
Expected: all three listed.

- [ ] **Step 2: Release build**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme xBill \
  -destination 'id=CA2078AC-6559-4BF3-93CB-370CF27E92EA' -configuration Release build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Add the fix-log entry to CLAUDE.md**

Insert a `## Recent Fix Log — 2026-08-29 — expense edits stop overwriting each other` section
above the previous dated entry. It must record: the defect; that the second write was found
during design and deleted; that the token is a `String` and why; that a nil token forces a
re-fetch; the `DEFAULT NULL` compatibility hinge and the fact that old clients can still clobber;
and the honest limit that no two-device race was exercised.

Also update the trap-index row for Settle Up / expenses to mention that expense edits now carry a
concurrency token and that `updated_at` is no longer unread.

- [ ] **Step 4: Add the AUDIT_REPORT.md rows**

Two rows: one for the concurrency defect, one for the double write found during design. Each with
ID, file, issue, status, fix — matching the existing table format.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md AUDIT_REPORT.md
git commit -m "Document the expense concurrency guard and the double write it uncovered"
```

- [ ] **Step 6: Report honestly**

State in the final summary, without softening:
- the suite count and that suites were confirmed by name;
- that the guard was verified against production read-only in Task 2, Step 5;
- **that no two-device race was exercised** — the mechanism is proven, the race is not;
- **that clients on 1.0–1.5 can still clobber**, and will until they update.

---

## Self-Review

**Spec coverage.** Migration with `updated_by`, backfill, `NOT NULL DEFAULT now()` → Task 1.
DROP+CREATE with the H-11 rationale, grants re-issued, `anon` revoked by name → Task 1.
`p_expected_updated_at DEFAULT NULL` and the XB409 branch → Task 1. Deploy and live read-only
verification → Task 2. Opaque string token, optional for cache compatibility → Task 3. Always-sent
key, never `encodeIfPresent` → Task 4. Exact-code matching, mutation-tested → Task 5. Second write
deleted, `applySavedExpense` with zero fetches → Task 6. Nil-token re-fetch, refuse-and-reload copy
naming the editor → Task 7. Honest limits → Task 8, Step 6. **No gaps.**

**Placeholder scan.** No TBD/TODO. Every code step carries real code. Two steps ask the
implementer to confirm a property name (`GroupViewModel.init` label, the members property in
`ExpenseDetailView`) before writing — these are verification instructions with a stated fallback,
not placeholders.

**Type consistency.** `updatedAt: String?` is used as a `String?` in Tasks 3, 4 and 7.
`expectedUpdatedAt: String?` is the label in `makeUpdateParams`, `updateParamsJSON` and
`updateExpenseWithSplits` in Task 4 and used with that label in Task 7. `applySavedExpense(_:)` is
defined in Task 6 and called with that name in Task 6, Step 5. `AppError.isEditConflict` is defined
in Task 5 and used in Task 7.

**One correction folded in:** the spec said `GroupDataProviding.updateExpense`. It is actually on
**`ExpenseDataProviding`** (`GroupDataProviding.swift`, same file). Task 6 targets the correct
protocol.

**One typo caught and fixed inline:** `editConflictCode` in Task 5 had been written with a Cyrillic
*С*, which would have failed to compile against its own usage two lines below.

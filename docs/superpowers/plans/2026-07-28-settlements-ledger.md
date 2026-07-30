# Settlements Ledger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `splits.is_settled` boolean with a `settlements` ledger, so payments are recorded as attributable rows and balances are derived by arithmetic.

**Architecture:** A payment becomes one row in a new `public.settlements` table (`from_user_id`, `to_user_id`, `amount`, `recorded_by`). Balances are computed in two passes — every split counts as debt, then every settlement offsets it. `splits.is_settled` stops being read or written. Either party may record a payment; only the recorder may delete it.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, Supabase (PostgREST + RLS), Deno Edge Functions, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-07-28-settlements-ledger-design.md`

## Global Constraints

- Swift 6 strict concurrency. Services and view models are `@MainActor`.
- Every mutating PostgREST call goes through `SupabaseWrite.requireAffected`. Never `.single()` for an affected-row check.
- Money is `Decimal`. Round with `NSDecimalRound(&out, &in, 2, .bankers)`. Never `Double`.
- New Swift files require `xcodegen generate` before they compile.
- Test command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:xBillTests`
- Full check: `scripts/run-coverage.sh unit`
- **No migration is applied to the live database in this plan.** Task 3 writes and locally verifies it; Task 9 stops at a deployment gate requiring explicit user approval.
- `Settlement.PaymentMethod` is **live** (`PaymentLinkService`, `ProfileView`). It stays nested inside `Settlement` so no call site changes.
- Physical device: iPhone 16 Pro `00008140-000135EE3432801C`.

---

## File Structure

| File | Responsibility |
|---|---|
| `xBill/Models/Settlement.swift` | **Modify.** Replace the dead speculative struct with the ledger row. Keep `PaymentMethod` nested. Keep `SettlementSuggestion`. |
| `xBill/Services/SettlementService.swift` | **Create.** Fetch / insert / delete settlements. |
| `xBill/Services/SplitCalculator.swift` | **Modify.** `netBalances` takes settlements; `directSettlementSuggestions` nets pairs. |
| `xBill/Services/GroupDataProviding.swift` | **Modify.** Add `SettlementDataProviding`. |
| `xBill/ViewModels/GroupViewModel.swift` | **Modify.** Load settlements, record, delete. Delete `locallyConfirmedSettledSplitIDs` and the split-matching logic. |
| `xBill/Views/Groups/RecordPaymentSheet.swift` | **Create.** Amount entry, pre-filled with the outstanding figure. |
| `xBill/Views/Groups/PaymentHistorySection.swift` | **Create.** Recent payments list with swipe-to-delete. |
| `xBill/Views/Groups/GroupDetailView.swift` | **Modify.** Settle Up rows gated; wire the sheet and history. |
| `xBill/Views/Expenses/ExpenseDetailView.swift` | **Modify.** Remove the per-split Settled marker. |
| `supabase/migrations/041_settlements.sql` | **Create.** Table, indexes, RLS, backfill, verification. |
| `supabase/functions/notify-settlement/index.ts` | **Modify.** Derive parties from the settlement row, not the caller. |
| `xBillTests/SettlementLedgerTests.swift` | **Create.** Balance arithmetic and model coding. |
| `xBillTests/GroupViewModelSettlementTests.swift` | **Create.** View-model record/delete with fakes. |

---

## Task 1: Settlement ledger model

**Files:**
- Modify: `xBill/Models/Settlement.swift`
- Test: `xBillTests/SettlementLedgerTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `struct Settlement` with `id: UUID`, `groupID: UUID`, `fromUserID: UUID`, `toUserID: UUID`, `amount: Decimal`, `currency: String`, `recordedBy: UUID`, `createdAt: Date`. Nested `Settlement.PaymentMethod` unchanged. `SettlementSuggestion` unchanged.

- [ ] **Step 1: Write the failing test**

Create `xBillTests/SettlementLedgerTests.swift`:

```swift
import Foundation
import Testing
@testable import xBill

@Suite("Settlement row coding")
struct SettlementCodingTests {

    @Test("Decodes the PostgREST row shape")
    func decodesRow() throws {
        let id = UUID(), group = UUID(), from = UUID(), to = UUID(), by = UUID()
        let json = """
        {"id":"\(id.uuidString)","group_id":"\(group.uuidString)",
         "from_user_id":"\(from.uuidString)","to_user_id":"\(to.uuidString)",
         "amount":10.5,"currency":"USD","recorded_by":"\(by.uuidString)",
         "created_at":"2026-07-28T12:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let s = try decoder.decode(Settlement.self, from: Data(json.utf8))

        #expect(s.id == id)
        #expect(s.groupID == group)
        #expect(s.fromUserID == from)
        #expect(s.toUserID == to)
        #expect(s.amount == Decimal(string: "10.5"))
        #expect(s.recordedBy == by)
    }

    /// `Settlement.PaymentMethod` is used by PaymentLinkService and ProfileView.
    /// Replacing the struct must not remove it.
    @Test("PaymentMethod is still reachable")
    func paymentMethodSurvives() {
        #expect(Settlement.PaymentMethod.paypal.rawValue == "paypal")
        #expect(Settlement.PaymentMethod.venmo.rawValue == "venmo")
    }
}
```

- [ ] **Step 2: Run it and verify it fails**

Run the test command with `-only-testing:xBillTests/SettlementCodingTests`.
Expected: compile failure — `Settlement` has no member `recordedBy`.

- [ ] **Step 3: Replace the struct**

In `xBill/Models/Settlement.swift`, replace the whole `struct Settlement { … }` (keeping the file's `SettlementSuggestion` below it) with:

```swift
/// One recorded payment. The ledger row that balances are derived from.
///
/// Replaces the old `splits.is_settled` flag: a payment is an amount from one person to
/// another, not a mutation of individual expense shares. See
/// `docs/superpowers/specs/2026-07-28-settlements-ledger-design.md`.
struct Settlement: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let groupID: UUID
    let fromUserID: UUID     // payer
    let toUserID: UUID       // recipient
    let amount: Decimal
    let currency: String
    let recordedBy: UUID
    let createdAt: Date

    /// Retained here because `PaymentLinkService` and `ProfileView` refer to
    /// `Settlement.PaymentMethod`. Not a property of a ledger row.
    enum PaymentMethod: String, Codable, Sendable {
        case cash         = "cash"
        case upi          = "upi"
        case paypal       = "paypal"
        case venmo        = "venmo"
        case bankTransfer = "bank_transfer"
        case other        = "other"
    }

    enum CodingKeys: String, CodingKey {
        case id, amount, currency
        case groupID    = "group_id"
        case fromUserID = "from_user_id"
        case toUserID   = "to_user_id"
        case recordedBy = "recorded_by"
        case createdAt  = "created_at"
    }
}
```

- [ ] **Step 4: Regenerate and run**

```bash
cd /Users/vijaygoyal/MyiOSApp/xBill && xcodegen generate
```
Run the test command. Expected: PASS. Also run the **whole** `xBillTests` suite — `PaymentLinkService` and `ProfileView` must still compile.

- [ ] **Step 5: Commit**

```bash
git add xBill/Models/Settlement.swift xBillTests/SettlementLedgerTests.swift xBill.xcodeproj
git commit -m "Add settlement ledger row model"
```

---

## Task 2: Balance computation from settlements

**Files:**
- Modify: `xBill/Services/SplitCalculator.swift`
- Test: `xBillTests/SettlementLedgerTests.swift`

**Interfaces:**
- Consumes: `Settlement` from Task 1.
- Produces:
  - `SplitCalculator.netBalances(expenses:splits:settlements:) -> [UUID: Decimal]`
  - `SplitCalculator.settlementSuggestions(expenses:splits:settlements:names:currency:) -> [SettlementSuggestion]` (replaces `directSettlementSuggestions`)

- [ ] **Step 1: Write the failing tests**

Append to `xBillTests/SettlementLedgerTests.swift`:

```swift
@MainActor
private func expense(payer: UUID, group: UUID, amount: Decimal = 30) -> Expense {
    Expense(id: UUID(), groupID: group, title: "Dinner", amount: amount, currency: "USD",
            payerID: payer, category: .food, notes: nil, receiptURL: nil,
            originalAmount: nil, originalCurrency: nil, recurrence: .none,
            nextOccurrenceDate: nil, createdAt: Date())
}

@MainActor
private func split(_ expenseID: UUID, _ userID: UUID, _ amount: Decimal) -> Split {
    Split(id: UUID(), expenseID: expenseID, userID: userID, amount: amount,
          isSettled: false, settledAt: nil)
}

@MainActor
private func payment(_ group: UUID, from: UUID, to: UUID, _ amount: Decimal) -> Settlement {
    Settlement(id: UUID(), groupID: group, fromUserID: from, toUserID: to,
               amount: amount, currency: "USD", recordedBy: from, createdAt: Date())
}

@Suite("Balances from expenses and settlements")
@MainActor
struct LedgerBalanceTests {

    @Test("With no payments, every split is debt")
    func debtOnly() {
        let g = UUID(), alice = UUID(), bob = UUID()
        let e = expense(payer: alice, group: g)
        let balances = SplitCalculator.netBalances(
            expenses: [e], splits: [e.id: [split(e.id, bob, 10)]], settlements: [])
        #expect(balances[alice] == 10)
        #expect(balances[bob] == -10)
    }

    @Test("A payment offsets the debt exactly")
    func exactPayment() {
        let g = UUID(), alice = UUID(), bob = UUID()
        let e = expense(payer: alice, group: g)
        let balances = SplitCalculator.netBalances(
            expenses: [e], splits: [e.id: [split(e.id, bob, 10)]],
            settlements: [payment(g, from: bob, to: alice, 10)])
        #expect(balances[alice] == 0)
        #expect(balances[bob] == 0)
    }

    @Test("A partial payment leaves the remainder owing")
    func partialPayment() {
        let g = UUID(), alice = UUID(), bob = UUID()
        let e = expense(payer: alice, group: g)
        let balances = SplitCalculator.netBalances(
            expenses: [e], splits: [e.id: [split(e.id, bob, 30)]],
            settlements: [payment(g, from: bob, to: alice, 10)])
        #expect(balances[bob] == -20)
    }

    /// Free-form amounts mean over-payment is expressible. It reverses the direction,
    /// which is what actually happened.
    @Test("Over-payment reverses the direction")
    func overPayment() {
        let g = UUID(), alice = UUID(), bob = UUID()
        let e = expense(payer: alice, group: g)
        let balances = SplitCalculator.netBalances(
            expenses: [e], splits: [e.id: [split(e.id, bob, 20)]],
            settlements: [payment(g, from: bob, to: alice, 50)])
        #expect(balances[bob] == 30)
        #expect(balances[alice] == -30)
    }

    /// `is_settled` must no longer influence anything.
    @Test("A split flagged settled still counts as debt")
    func flagIsIgnored() {
        let g = UUID(), alice = UUID(), bob = UUID()
        let e = expense(payer: alice, group: g)
        var s = split(e.id, bob, 10)
        s.isSettled = true
        let balances = SplitCalculator.netBalances(
            expenses: [e], splits: [e.id: [s]], settlements: [])
        #expect(balances[bob] == -10)
    }
}

@Suite("Settlement suggestions from the ledger")
@MainActor
struct LedgerSuggestionTests {

    @Test("Mutual debts net to a single row")
    func mutualDebtsNet() {
        let g = UUID(), alice = UUID(), bob = UUID()
        let e1 = expense(payer: alice, group: g)   // bob owes alice 10
        let e2 = expense(payer: bob, group: g)     // alice owes bob 6

        let suggestions = SplitCalculator.settlementSuggestions(
            expenses: [e1, e2],
            splits: [e1.id: [split(e1.id, bob, 10)], e2.id: [split(e2.id, alice, 6)]],
            settlements: [],
            names: [alice: "Alice", bob: "Bob"],
            currency: "USD")

        #expect(suggestions.count == 1)
        #expect(suggestions.first?.fromUserID == bob)
        #expect(suggestions.first?.toUserID == alice)
        #expect(suggestions.first?.amount == 4)
    }

    @Test("A fully paid pair produces no suggestion")
    func paidPairDisappears() {
        let g = UUID(), alice = UUID(), bob = UUID()
        let e = expense(payer: alice, group: g)
        let suggestions = SplitCalculator.settlementSuggestions(
            expenses: [e], splits: [e.id: [split(e.id, bob, 10)]],
            settlements: [payment(g, from: bob, to: alice, 10)],
            names: [alice: "Alice", bob: "Bob"], currency: "USD")
        #expect(suggestions.isEmpty)
    }

    @Test("Sub-cent residue produces no suggestion")
    func subCentIgnored() {
        let g = UUID(), alice = UUID(), bob = UUID()
        let e = expense(payer: alice, group: g)
        let suggestions = SplitCalculator.settlementSuggestions(
            expenses: [e], splits: [e.id: [split(e.id, bob, Decimal(string: "10.004")!)]],
            settlements: [payment(g, from: bob, to: alice, 10)],
            names: [alice: "Alice", bob: "Bob"], currency: "USD")
        #expect(suggestions.isEmpty)
    }
}
```

- [ ] **Step 2: Run and verify failure**

Expected: compile failure — `netBalances` has no `settlements:` parameter and `settlementSuggestions` does not exist.

- [ ] **Step 3: Implement**

In `SplitCalculator.swift`, replace `netBalances` and `directSettlementSuggestions`:

```swift
    /// Positive = is owed money. Negative = owes money.
    ///
    /// Two passes. Every split is debt — `is_settled` is deliberately not consulted, because
    /// repayment is recorded in `settlements`, not on the share.
    static func netBalances(
        expenses: [Expense],
        splits: [UUID: [Split]],
        settlements: [Settlement]
    ) -> [UUID: Decimal] {
        var balances: [UUID: Decimal] = [:]

        for expense in expenses {
            guard let payerID = expense.payerID else { continue }
            for split in splits[expense.id] ?? [] {
                guard split.userID != payerID else { continue }
                var amount = split.amount
                var rounded = Decimal()
                NSDecimalRound(&rounded, &amount, 2, .bankers)
                balances[payerID, default: .zero]      += rounded
                balances[split.userID, default: .zero] -= rounded
            }
        }

        for settlement in settlements {
            var amount = settlement.amount
            var rounded = Decimal()
            NSDecimalRound(&rounded, &amount, 2, .bankers)
            balances[settlement.fromUserID, default: .zero] += rounded
            balances[settlement.toUserID, default: .zero]   -= rounded
        }

        return balances
    }

    /// Per-pair outstanding amounts, netted in both directions.
    ///
    /// Netting is safe here in a way it was not before: a suggestion no longer has to map
    /// onto whole split rows, so an amount that matches no individual split is still
    /// recordable as a payment (REV-13).
    static func settlementSuggestions(
        expenses: [Expense],
        splits: [UUID: [Split]],
        settlements: [Settlement],
        names: [UUID: String],
        currency: String
    ) -> [SettlementSuggestion] {
        struct Pair: Hashable { let a: UUID; let b: UUID }

        /// Canonical key so A→B and B→A accumulate into one entry.
        func key(_ x: UUID, _ y: UUID) -> Pair {
            x.uuidString < y.uuidString ? Pair(a: x, b: y) : Pair(a: y, b: x)
        }

        // Positive value = `a` owes `b`.
        var net: [Pair: Decimal] = [:]

        func add(debtor: UUID, creditor: UUID, _ amount: Decimal) {
            var value = amount
            var rounded = Decimal()
            NSDecimalRound(&rounded, &value, 2, .bankers)
            let k = key(debtor, creditor)
            net[k, default: .zero] += (k.a == debtor ? rounded : -rounded)
        }

        for expense in expenses {
            guard let creditorID = expense.payerID else { continue }
            for split in splits[expense.id] ?? [] where split.userID != creditorID {
                add(debtor: split.userID, creditor: creditorID, split.amount)
            }
        }
        for settlement in settlements {
            // A payment reduces what the payer owes.
            add(debtor: settlement.toUserID, creditor: settlement.fromUserID, settlement.amount)
        }

        let epsilon = Decimal(string: "0.005") ?? Decimal(5) / Decimal(1000)

        return net.compactMap { pair, value -> SettlementSuggestion? in
            let magnitude = value < .zero ? -value : value
            guard magnitude > epsilon else { return nil }
            let debtor   = value > .zero ? pair.a : pair.b
            let creditor = value > .zero ? pair.b : pair.a
            var rounded = Decimal()
            var m = magnitude
            NSDecimalRound(&rounded, &m, 2, .bankers)
            return SettlementSuggestion(
                id: UUID(),
                fromUserID: debtor,  fromName: names[debtor] ?? "Unknown",
                toUserID: creditor,  toName: names[creditor] ?? "Unknown",
                amount: rounded, currency: currency)
        }
        .sorted {
            $0.fromUserID != $1.fromUserID
                ? $0.fromUserID.uuidString < $1.fromUserID.uuidString
                : $0.toUserID.uuidString < $1.toUserID.uuidString
        }
    }
```

Leave `minimizeTransactions` untouched — `HomeViewModel` still uses it for the display-only cross-group list.

- [ ] **Step 4: Fix the two existing call sites so the project compiles**

`GroupViewModel.swift` — pass `settlements: []` temporarily at both `netBalances` call sites and rename `directSettlementSuggestions` to `settlementSuggestions(… settlements: [] …)`. Task 4 replaces the empty arrays with real data.

`HomeViewModel.swift:318` region — `netBalances(expenses:splits:)` becomes `netBalances(expenses:splits:settlements: [])`. Home balances gain settlement support in Task 4.

- [ ] **Step 5: Run the full suite**

Expected: PASS. Old `SplitCalculatorTests` cases asserting settled splits are skipped will now fail — **delete those assertions**, they pin behaviour this task deliberately removes. Do not weaken the new tests to accommodate them.

- [ ] **Step 6: Commit**

```bash
git add xBill/Services/SplitCalculator.swift xBill/ViewModels xBillTests
git commit -m "Derive balances from settlements instead of is_settled"
```

---

## Task 3: Migration and backfill (written and locally verified, NOT deployed)

**Files:**
- Create: `supabase/migrations/041_settlements.sql`

**Interfaces:**
- Consumes: nothing.
- Produces: `public.settlements` table used by Task 5.

- [ ] **Step 1: Write the migration**

```sql
-- Migration 041: settlements ledger.
--
-- Replaces `splits.is_settled` as the record of who has paid whom. A payment is its own
-- row — attributable, deletable, and an arbitrary amount — so balances are derived by
-- arithmetic rather than by flipping flags on individual expense shares.
--
-- See docs/superpowers/specs/2026-07-28-settlements-ledger-design.md
-- `splits.is_settled` is intentionally left in place, unread and unwritten, for one
-- release so the original state can be re-derived if the backfill proves wrong.

CREATE TABLE IF NOT EXISTS public.settlements (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id     uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    from_user_id uuid NOT NULL,
    to_user_id   uuid NOT NULL,
    amount       numeric(20, 2) NOT NULL CHECK (amount > 0),
    currency     text NOT NULL,
    recorded_by  uuid NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT settlements_distinct_parties CHECK (from_user_id <> to_user_id)
);

-- No FK on the three user columns: migration 035 set this precedent for splits.user_id.
-- If an account is deleted the payment history must survive, or every other member's
-- balance silently changes.

CREATE INDEX IF NOT EXISTS settlements_group_created_idx
    ON public.settlements (group_id, created_at DESC);
CREATE INDEX IF NOT EXISTS settlements_group_pair_idx
    ON public.settlements (group_id, from_user_id, to_user_id);

ALTER TABLE public.settlements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "settlements: group members read" ON public.settlements;
CREATE POLICY "settlements: group members read"
    ON public.settlements FOR SELECT
    USING (public.is_group_member(group_id));

DROP POLICY IF EXISTS "settlements: a party records their own" ON public.settlements;
CREATE POLICY "settlements: a party records their own"
    ON public.settlements FOR INSERT
    WITH CHECK (
        recorded_by = auth.uid()
        AND auth.uid() IN (from_user_id, to_user_id)
        AND public.is_group_member(group_id)
        -- Both parties must belong to the group, or a member could insert a payment
        -- against an arbitrary UUID. is_active is deliberately NOT required: someone who
        -- has left the group can still owe money that needs settling.
        AND EXISTS (SELECT 1 FROM public.group_members gm
                     WHERE gm.group_id = settlements.group_id AND gm.user_id = from_user_id)
        AND EXISTS (SELECT 1 FROM public.group_members gm
                     WHERE gm.group_id = settlements.group_id AND gm.user_id = to_user_id)
    );

DROP POLICY IF EXISTS "settlements: recorder deletes" ON public.settlements;
CREATE POLICY "settlements: recorder deletes"
    ON public.settlements FOR DELETE
    USING (recorded_by = auth.uid());

-- No UPDATE policy: corrections are delete-then-record.

-- Backfill: one settlement per settled split. recorded_by is the debtor because, under the
-- RLS in force until now (auth.uid() = user_id), only the debtor could have settled it.
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

- [ ] **Step 2: Write the balance-equivalence check as a standalone script**

Create `scripts/verify-settlements-backfill.sql` (run manually, not part of the migration):

```sql
-- Old model: unsettled splits only. New model: all splits, minus settlements.
-- Every row returned is a user whose balance changed. Expect ZERO rows.
WITH old_balances AS (
    SELECT e.paid_by AS user_id, SUM(s.amount) AS delta
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE NOT s.is_settled AND e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
     GROUP BY e.paid_by
    UNION ALL
    SELECT s.user_id, -SUM(s.amount)
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE NOT s.is_settled AND e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
     GROUP BY s.user_id
),
new_balances AS (
    SELECT e.paid_by AS user_id, SUM(s.amount) AS delta
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
     GROUP BY e.paid_by
    UNION ALL
    SELECT s.user_id, -SUM(s.amount)
      FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id
     WHERE e.paid_by IS NOT NULL AND e.paid_by <> s.user_id
     GROUP BY s.user_id
    UNION ALL
    SELECT from_user_id, SUM(amount) FROM public.settlements GROUP BY from_user_id
    UNION ALL
    SELECT to_user_id, -SUM(amount) FROM public.settlements GROUP BY to_user_id
)
SELECT COALESCE(o.user_id, n.user_id) AS user_id,
       COALESCE(SUM(o.delta), 0) AS old_balance,
       COALESCE(SUM(n.delta), 0) AS new_balance
  FROM old_balances o FULL OUTER JOIN new_balances n ON o.user_id = n.user_id
 GROUP BY 1
HAVING COALESCE(SUM(o.delta), 0) <> COALESCE(SUM(n.delta), 0);
```

- [ ] **Step 3: Verify the backfill predicate against production, read-only**

```bash
supabase db query --linked "SELECT count(*) AS will_backfill FROM public.splits s JOIN public.expenses e ON e.id = s.expense_id WHERE s.is_settled AND e.paid_by IS NOT NULL AND e.paid_by <> s.user_id;"
```
Expected: **2**.

There are 7 settled splits, but 5 are the payer's own share (`paid_by = user_id`), which the
predicate correctly excludes: they are balance-neutral in both models and would violate the
`settlements_distinct_parties` CHECK. If the answer is not 2, stop and report.

- [ ] **Step 4: Commit. Do NOT deploy.**

```bash
git add supabase/migrations/041_settlements.sql scripts/verify-settlements-backfill.sql
git commit -m "Add settlements migration and backfill verification (not deployed)"
```

**Do not run `supabase db push`.** Task 9 handles the deployment gate.

---

## Task 4: SettlementService and the data-provider seam

**Files:**
- Create: `xBill/Services/SettlementService.swift`
- Modify: `xBill/Services/GroupDataProviding.swift`

**Interfaces:**
- Consumes: `Settlement` (Task 1), `SupabaseWrite.requireAffected`, `AffectedRowID`.
- Produces: `protocol SettlementDataProviding` with
  `fetchSettlements(groupID: UUID) async throws -> [Settlement]`,
  `recordSettlement(groupID: UUID, fromUserID: UUID, toUserID: UUID, amount: Decimal, currency: String, recordedBy: UUID) async throws -> Settlement`,
  `deleteSettlement(id: UUID) async throws`.
  `SettlementService.shared` conforms.

- [ ] **Step 1: Write the failing test**

Append to `xBillTests/SettlementLedgerTests.swift`:

```swift
@Suite("Settlement insert payload")
struct SettlementPayloadTests {

    @Test("Insert payload uses snake_case column names")
    func payloadKeys() throws {
        let payload = SettlementInsert(
            groupID: UUID(), fromUserID: UUID(), toUserID: UUID(),
            amount: Decimal(string: "12.50")!, currency: "USD", recordedBy: UUID())

        let data = try SupabaseManager.postgrestEncoder.encode(payload)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["group_id"] != nil)
        #expect(json["from_user_id"] != nil)
        #expect(json["to_user_id"] != nil)
        #expect(json["recorded_by"] != nil)
        #expect(json["currency"] as? String == "USD")
        // created_at is a server default — never sent.
        #expect(json["created_at"] == nil)
        #expect(json["id"] == nil)
    }
}
```

- [ ] **Step 2: Run and verify failure**

Expected: compile failure — `SettlementInsert` not found.

- [ ] **Step 3: Create the service**

`xBill/Services/SettlementService.swift`:

```swift
import Foundation

/// The body of a settlement INSERT. `id` and `created_at` are server defaults.
struct SettlementInsert: Encodable {
    let groupID: UUID
    let fromUserID: UUID
    let toUserID: UUID
    let amount: Decimal
    let currency: String
    let recordedBy: UUID

    enum CodingKeys: String, CodingKey {
        case amount, currency
        case groupID    = "group_id"
        case fromUserID = "from_user_id"
        case toUserID   = "to_user_id"
        case recordedBy = "recorded_by"
    }
}

@MainActor
protocol SettlementDataProviding: AnyObject, Sendable {
    func fetchSettlements(groupID: UUID) async throws -> [Settlement]
    func recordSettlement(
        groupID: UUID, fromUserID: UUID, toUserID: UUID,
        amount: Decimal, currency: String, recordedBy: UUID
    ) async throws -> Settlement
    func deleteSettlement(id: UUID) async throws
}

@MainActor
final class SettlementService: SettlementDataProviding {
    static let shared = SettlementService()
    private let supabase = SupabaseManager.shared
    private init() {}

    func fetchSettlements(groupID: UUID) async throws -> [Settlement] {
        try await supabase.table("settlements")
            .select()
            .eq("group_id", value: groupID)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Returns the inserted row. `.select().single()` is correct here — an INSERT that
    /// succeeds returns exactly one row, and a row is genuinely required by the caller.
    /// Contrast the delete below, where zero rows is the failure being detected.
    func recordSettlement(
        groupID: UUID, fromUserID: UUID, toUserID: UUID,
        amount: Decimal, currency: String, recordedBy: UUID
    ) async throws -> Settlement {
        try await supabase.table("settlements")
            .insert(SettlementInsert(
                groupID: groupID, fromUserID: fromUserID, toUserID: toUserID,
                amount: amount, currency: currency, recordedBy: recordedBy))
            .select()
            .single()
            .execute()
            .value
    }

    func deleteSettlement(id: UUID) async throws {
        let rows: [AffectedRowID] = try await supabase.table("settlements")
            .delete()
            .eq("id", value: id)
            .select("id")
            .execute()
            .value
        try SupabaseWrite.requireAffected(rows, table: "settlements", id: id)
    }
}
```

- [ ] **Step 4: Regenerate, run, commit**

```bash
xcodegen generate
```
Run the full `xBillTests` suite. Expected: PASS.

```bash
git add xBill/Services/SettlementService.swift xBillTests xBill.xcodeproj
git commit -m "Add SettlementService with affected-row delete check"
```

---

## Task 5: GroupViewModel records and deletes payments

**Files:**
- Modify: `xBill/ViewModels/GroupViewModel.swift`
- Test: `xBillTests/GroupViewModelSettlementTests.swift` (create)

**Interfaces:**
- Consumes: `SettlementDataProviding` (Task 4), `settlementSuggestions` (Task 2).
- Produces on `GroupViewModel`: `var settlements: [Settlement]`,
  `func recordPayment(from:to:amount:) async`, `func deletePayment(_ settlement: Settlement) async`,
  and an `init(group:groupService:expenseService:settlementService:currentUserIDProvider:)`.

- [ ] **Step 1: Write the failing tests**

Create `xBillTests/GroupViewModelSettlementTests.swift`:

```swift
import Foundation
import Testing
@testable import xBill

@MainActor
final class FakeSettlementService: SettlementDataProviding {
    var stored: [Settlement] = []
    var insertError: Error?
    var deleteError: Error?
    var deletedIDs: [UUID] = []

    func fetchSettlements(groupID: UUID) async throws -> [Settlement] { stored }

    func recordSettlement(groupID: UUID, fromUserID: UUID, toUserID: UUID,
                          amount: Decimal, currency: String, recordedBy: UUID) async throws -> Settlement {
        if let insertError { throw insertError }
        let s = Settlement(id: UUID(), groupID: groupID, fromUserID: fromUserID,
                           toUserID: toUserID, amount: amount, currency: currency,
                           recordedBy: recordedBy, createdAt: Date())
        stored.append(s)
        return s
    }

    func deleteSettlement(id: UUID) async throws {
        if let deleteError { throw deleteError }
        deletedIDs.append(id)
        stored.removeAll { $0.id == id }
    }
}

@Suite("GroupViewModel payments", .serialized)
@MainActor
struct GroupViewModelPaymentTests {

    private func makeGroup() -> BillGroup {
        BillGroup(id: UUID(), name: "Trip", emoji: "✈️", createdBy: UUID(),
                  isArchived: false, currency: "USD", createdAt: Date())
    }

    @Test("Recording a payment reduces the balance")
    func recordReducesBalance() async {
        let group = makeGroup(); let alice = UUID(); let bob = UUID()
        let expenses = FakeExpenseService(); let settlements = FakeSettlementService()
        let e = Expense(id: UUID(), groupID: group.id, title: "Dinner", amount: 30,
                        currency: "USD", payerID: alice, category: .food, notes: nil,
                        receiptURL: nil, originalAmount: nil, originalCurrency: nil,
                        recurrence: .none, nextOccurrenceDate: nil, createdAt: Date())
        expenses.expenses = [e]
        expenses.splits = [Split(id: UUID(), expenseID: e.id, userID: bob, amount: 10,
                                 isSettled: false, settledAt: nil)]

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: expenses, settlementService: settlements,
                                currentUserIDProvider: { bob })
        await vm.load(showError: false)
        #expect(vm.balance(for: bob) == -10)

        await vm.recordPayment(from: bob, to: alice, amount: 10)

        #expect(vm.balance(for: bob) == 0)
        #expect(settlements.stored.count == 1)
        #expect(settlements.stored.first?.recordedBy == bob)
        #expect(vm.errorAlert == nil)
    }

    @Test("A failed insert surfaces an error and records nothing")
    func failedInsertIsReported() async {
        let group = makeGroup(); let alice = UUID(); let bob = UUID()
        let settlements = FakeSettlementService()
        settlements.insertError = AppError.permissionDenied

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: FakeExpenseService(),
                                settlementService: settlements,
                                currentUserIDProvider: { bob })

        await vm.recordPayment(from: bob, to: alice, amount: 10)

        #expect(settlements.stored.isEmpty)
        #expect(vm.errorAlert != nil)
    }

    @Test("Deleting a payment restores the balance")
    func deleteRestoresBalance() async {
        let group = makeGroup(); let alice = UUID(); let bob = UUID()
        let expenses = FakeExpenseService(); let settlements = FakeSettlementService()
        let e = Expense(id: UUID(), groupID: group.id, title: "Dinner", amount: 30,
                        currency: "USD", payerID: alice, category: .food, notes: nil,
                        receiptURL: nil, originalAmount: nil, originalCurrency: nil,
                        recurrence: .none, nextOccurrenceDate: nil, createdAt: Date())
        expenses.expenses = [e]
        expenses.splits = [Split(id: UUID(), expenseID: e.id, userID: bob, amount: 10,
                                 isSettled: false, settledAt: nil)]

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: expenses, settlementService: settlements,
                                currentUserIDProvider: { bob })
        await vm.load(showError: false)
        await vm.recordPayment(from: bob, to: alice, amount: 10)
        #expect(vm.balance(for: bob) == 0)

        let payment = try! #require(vm.settlements.first)
        await vm.deletePayment(payment)

        #expect(vm.balance(for: bob) == -10)
        #expect(settlements.deletedIDs == [payment.id])
    }
}
```

- [ ] **Step 2: Run and verify failure**

Expected: compile failure — `GroupViewModel` has no `settlementService:` parameter, no `settlements`, no `recordPayment`.

- [ ] **Step 3: Implement in `GroupViewModel.swift`**

1. Add state and dependency:

```swift
    var settlements: [Settlement] = []
    private let settlementService: any SettlementDataProviding
    private let currentUserIDProvider: @MainActor () -> UUID?
```

2. Extend `init` (keep the existing defaults so no call site breaks):

```swift
    init(
        group: BillGroup,
        groupService: any GroupDataProviding = GroupService.shared,
        expenseService: any ExpenseDataProviding = ExpenseService.shared,
        settlementService: any SettlementDataProviding = SettlementService.shared,
        currentUserIDProvider: @escaping @MainActor () -> UUID? = { AuthService.shared.currentUserID }
    ) {
        self.settlementService = settlementService
        self.currentUserIDProvider = currentUserIDProvider
        // …existing assignments unchanged…
    }
```

3. In `load()`'s connected branch, fetch settlements alongside members and expenses:

```swift
                let settlementService = settlementService
                let (fetchedMembers, fetchedExpenses, fetchedSettlements) =
                    try await withTimeout(duration: .seconds(12)) {
                        async let membersTask     = groupService.fetchMembers(groupID: groupID, includeInactive: true)
                        async let expensesTask    = expenseService.fetchExpenses(groupID: groupID, limit: nil)
                        async let settlementsTask = settlementService.fetchSettlements(groupID: groupID)
                        return try await (membersTask, expensesTask, settlementsTask)
                    }
                members = fetchedMembers
                settlements = fetchedSettlements
```

4. In `computeBalances()`, pass settlements to both calls:

```swift
            balances = SplitCalculator.netBalances(
                expenses: expenses, splits: splitsMap, settlements: settlements)
            settlementSuggestions = SplitCalculator.settlementSuggestions(
                expenses: expenses, splits: splitsMap, settlements: settlements,
                names: memberNames, currency: group.currency)
```

5. **Delete** `locallyConfirmedSettledSplitIDs`, its `formUnion` call, and the loop in
   `computeBalances` that overrides `isSettled` on fetched splits. It existed only to paper
   over read-after-write on split flags.

6. **Replace** the whole `recordSettlement(_:)` method — including the candidate-split
   matching, the task group, the partial-failure handling and the local split mutation —
   with:

```swift
    /// Records a payment. Either party may do this; the database enforces it.
    func recordPayment(from fromUserID: UUID, to toUserID: UUID, amount: Decimal) async {
        guard let recordedBy = currentUserIDProvider() else {
            errorAlert = ErrorAlert(title: "Not Signed In", message: "Sign in to record a payment.")
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let saved = try await settlementService.recordSettlement(
                groupID: group.id, fromUserID: fromUserID, toUserID: toUserID,
                amount: amount, currency: group.currency, recordedBy: recordedBy)
            settlements.insert(saved, at: 0)
            await computeBalances()

            let note = NotificationItem.settlement(
                suggestion: SettlementSuggestion(
                    id: saved.id, fromUserID: fromUserID, fromName: memberNames[fromUserID] ?? "Someone",
                    toUserID: toUserID, toName: memberNames[toUserID] ?? "Someone",
                    amount: amount, currency: group.currency),
                groupName: group.name, groupEmoji: group.emoji)
            NotificationStore.shared.merge([note], userID: fromUserID)

            if CacheService.defaults.bool(forKey: NotificationService.settlementPreferenceKey) {
                await expenseService.notifySettlementRecorded(
                    settlementID: saved.id, groupID: group.id,
                    toUserID: toUserID, amount: amount, currency: group.currency)
            }
        } catch {
            guard !AppError.isSilent(error) else { return }
            errorAlert = ErrorAlert(title: "Payment Not Recorded", message: error.localizedDescription)
        }
    }

    /// Removes a payment. RLS permits this only for the account that recorded it.
    func deletePayment(_ settlement: Settlement) async {
        isLoading = true
        defer { isLoading = false }
        let previous = settlements
        settlements.removeAll { $0.id == settlement.id }
        await computeBalances()
        do {
            try await settlementService.deleteSettlement(id: settlement.id)
        } catch {
            settlements = previous
            await computeBalances()
            guard !AppError.isSilent(error) else { return }
            errorAlert = ErrorAlert(title: "Payment Not Removed", message: error.localizedDescription)
        }
    }
```

7. In `HomeViewModel.fullBalancesInGroup`, fetch settlements for the group and pass them to
   `netBalances` so Home agrees with Group Detail. Use `SettlementService.shared`.

- [ ] **Step 4: Run tests**

Run the full `xBillTests` suite. Expected: PASS. The old `SettlementPartialFailureTests` will
no longer compile — **delete that suite**; it tested split-matching behaviour this task
removes. `DeletedExpenseTests` and `BalanceLoadFailedFlagTests` must still pass unchanged.

- [ ] **Step 5: Commit**

```bash
git add xBill/ViewModels xBillTests xBill.xcodeproj
git commit -m "Record and delete payments through the settlements ledger"
```

---

## Task 6: Record Payment sheet

**Files:**
- Create: `xBill/Views/Groups/RecordPaymentSheet.swift`

**Interfaces:**
- Consumes: `SettlementSuggestion`, `GroupViewModel.recordPayment(from:to:amount:)`.
- Produces: `RecordPaymentSheet(suggestion:currency:onConfirm:)` where `onConfirm` is
  `(Decimal) -> Void`.

- [ ] **Step 1: Create the view**

```swift
import SwiftUI

/// Amount entry for a payment, pre-filled with the full outstanding figure.
///
/// The amount is free-form on purpose: a payment is an amount one person gave another, not a
/// selection of expense shares. That is what makes partial payment expressible and what
/// removed the partial-settlement failure mode (REV-02).
struct RecordPaymentSheet: View {
    let suggestion: SettlementSuggestion
    let currency: String
    let onConfirm: (Decimal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String

    init(suggestion: SettlementSuggestion, currency: String, onConfirm: @escaping (Decimal) -> Void) {
        self.suggestion = suggestion
        self.currency = currency
        self.onConfirm = onConfirm
        _amountText = State(initialValue: NSDecimalNumber(decimal: suggestion.amount).stringValue)
    }

    private var enteredAmount: Decimal? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              value > .zero else { return nil }
        return value
    }

    private var exceedsOutstanding: Bool {
        guard let enteredAmount else { return false }
        return enteredAmount > suggestion.amount
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(suggestion.fromName) paid \(suggestion.toName)")
                        .font(.appBody)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.xbillLargeAmount)
                        .accessibilityIdentifier("xBill.recordPayment.amountField")
                } footer: {
                    if exceedsOutstanding {
                        Text("More than the \(suggestion.amount.formatted(currencyCode: currency)) outstanding. This will leave \(suggestion.toName) owing the difference.")
                            .foregroundStyle(Color.moneyNegative)
                    }
                }
            }
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Record") {
                        if let enteredAmount { onConfirm(enteredAmount) }
                        dismiss()
                    }
                    .disabled(enteredAmount == nil)
                    .accessibilityIdentifier("xBill.recordPayment.confirmButton")
                }
            }
        }
    }
}
```

- [ ] **Step 2: Regenerate, build, commit**

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17'
git add xBill/Views/Groups/RecordPaymentSheet.swift xBill.xcodeproj
git commit -m "Add Record Payment sheet"
```

---

## Task 7: Settle Up rows and payment history

**Files:**
- Create: `xBill/Views/Groups/PaymentHistorySection.swift`
- Modify: `xBill/Views/Groups/GroupDetailView.swift` (settle-up list and `settlementRow`)

**Interfaces:**
- Consumes: `RecordPaymentSheet` (Task 6), `GroupViewModel.settlements`, `deletePayment`.
- Produces: `PaymentHistorySection(settlements:memberNames:currency:currentUserID:onDelete:)`.

- [ ] **Step 1: Create the history section**

```swift
import SwiftUI

/// Recent payments, with attribution. Without this the ledger's two advantages over the old
/// boolean — knowing who recorded a payment, and being able to undo it — are invisible.
struct PaymentHistorySection: View {
    let settlements: [Settlement]
    let memberNames: [UUID: String]
    let currency: String
    let currentUserID: UUID?
    let onDelete: (Settlement) -> Void

    private func name(_ id: UUID) -> String { memberNames[id] ?? "Someone" }

    var body: some View {
        if !settlements.isEmpty {
            Section("Recent Payments") {
                ForEach(settlements) { settlement in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("\(name(settlement.fromUserID)) paid \(name(settlement.toUserID))")
                                .font(.appBody)
                            Spacer()
                            Text(settlement.amount.formatted(currencyCode: currency))
                                .font(.subheadline.monospacedDigit())
                        }
                        Text("recorded by \(name(settlement.recordedBy)) · \(settlement.createdAt.relativeFormatted)")
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .listRowBackground(Color.bgCard)
                    .accessibilityIdentifier("xBill.paymentHistory.row.\(settlement.id.uuidString)")
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // RLS permits deletion only by the recorder; showing it to anyone
                        // else would repeat the REV-01 mistake of offering an action the
                        // database will refuse.
                        if settlement.recordedBy == currentUserID {
                            Button(role: .destructive) { onDelete(settlement) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Gate the Settle Up row in `GroupDetailView.settlementRow`**

Replace the unconditional `XBillButton(title: "Mark as Settled", …)` with:

```swift
            let isParty = currentUserID == suggestion.fromUserID || currentUserID == suggestion.toUserID
            if isParty {
                XBillButton(title: "Record Payment", style: .primary) {
                    paymentToRecord = suggestion
                }
                .accessibilityIdentifier("xBill.settleUp.recordPaymentButton.\(suggestion.id.uuidString)")
            }
```

and apply `.opacity(isParty ? 1 : 0.55)` to the row's outer `VStack` so non-party rows read
as informational. Leave the existing `currentUserID == suggestion.fromUserID` payment-link
block untouched — it is already correctly gated.

- [ ] **Step 3: Wire the sheet and the history**

Add to `GroupDetailView`:

```swift
    @State private var paymentToRecord: SettlementSuggestion?
```

Add below the suggestions `ForEach` in the settle-up list:

```swift
                PaymentHistorySection(
                    settlements: vm.settlements,
                    memberNames: vm.memberNames,
                    currency: vm.group.currency,
                    currentUserID: currentUserID,
                    onDelete: { settlement in Task { await vm.deletePayment(settlement) } })
```

Add the sheet to `lifecycleContent`:

```swift
        .sheet(item: $paymentToRecord) { suggestion in
            RecordPaymentSheet(suggestion: suggestion, currency: vm.group.currency) { amount in
                Task {
                    await vm.recordPayment(
                        from: suggestion.fromUserID, to: suggestion.toUserID, amount: amount)
                }
            }
        }
```

Delete the old `settlementToConfirm` confirmation dialog and its state. The payment-return
prompt at the `handoffPrompt` site changes from `vm.recordSettlement(prompt.suggestion)` to
`paymentToRecord = prompt.suggestion`, so returning from a payment app opens the amount sheet.

- [ ] **Step 4: Build and commit**

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17'
git add xBill/Views/Groups xBill.xcodeproj
git commit -m "Gate settle-up rows and add payment history"
```

---

## Task 8: Remove the per-split Settled marker

**Files:**
- Modify: `xBill/Views/Expenses/ExpenseDetailView.swift:112-128`

- [ ] **Step 1: Remove the marker**

Delete the `if split.isSettled { Text("Settled …") }` block, and change

```swift
                                .foregroundStyle(split.isSettled ? .secondary : .primary)
```

to

```swift
                                .foregroundStyle(.primary)
```

An expense records what was spent and how it was shared. Whether a share has been repaid is
no longer a property of the expense — repayment is a separate fact in the ledger.

- [ ] **Step 2: Confirm nothing else reads split settlement state**

```bash
grep -rn "isSettled" --include="*.swift" xBill/ | grep -v "iou\|IOU"
```
Expected: only `Split.isSettled`'s declaration in `xBill/Models/Split.swift`. IOU hits are a
separate feature and stay.

- [ ] **Step 3: Build, test, commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17'
git add xBill/Views/Expenses/ExpenseDetailView.swift
git commit -m "Remove per-split settled marker from expense detail"
```

---

## Task 9: notify-settlement derives parties from the row

**Files:**
- Modify: `supabase/functions/notify-settlement/index.ts`

**Interfaces:**
- Consumes: the `settlements` table (Task 3).
- Produces: an Edge Function accepting `{ settlementId, isDevelopment }`.

- [ ] **Step 1: Understand what breaks**

The function sets `const fromUserID = callerID` (fix `H-09`: never trust a body-supplied
sender). That assumes the caller is the payer. Once a creditor can record, Alice recording
"Bob paid Alice" would be announced as *Alice* settling up and pushed to Alice herself.

- [ ] **Step 2: Replace the identity derivation**

After `requireAuth`, read the row with the service role and derive everything from it:

```ts
const { settlementId, isDevelopment } = await req.json()
if (!settlementId) {
  return new Response(JSON.stringify({ error: 'settlementId required' }),
    { status: 400, headers: corsHeaders })
}

const { data: settlement, error: settlementError } = await adminClient
  .from('settlements')
  .select('id, group_id, from_user_id, to_user_id, amount, currency, recorded_by')
  .eq('id', settlementId)
  .single()

if (settlementError || !settlement) {
  return new Response(JSON.stringify({ error: 'settlement not found' }),
    { status: 404, headers: corsHeaders })
}

// Preserves H-09 and strengthens it: nothing security-relevant comes from the body.
// The caller must be the account that recorded this payment.
if (settlement.recorded_by !== callerID) {
  return new Response(JSON.stringify({ error: 'forbidden' }),
    { status: 403, headers: corsHeaders })
}

const fromUserID = settlement.from_user_id
const toUserID   = settlement.to_user_id
// Notify whichever party did not record it.
const recipientID = callerID === fromUserID ? toUserID : fromUserID
```

Fetch `fromName` from `profiles` using `fromUserID` (not `callerID`). Send the push to
`recipientID`. Use `settlement.amount` and `settlement.currency`. Keep the existing JWT
cache, `apns-expiration`, stale-token cleanup and sandbox-URL logic unchanged.

- [ ] **Step 3: Update the Swift caller**

In `ExpenseService.notifySettlementRecorded`, replace the payload with
`{ settlementId, isDevelopment }` only. Remove `groupId`, `toUserID`, `amount`, `currency` —
the function now reads them from the row. Update `GroupViewModel.recordPayment` accordingly.

- [ ] **Step 4: Build and commit. Do NOT deploy.**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17'
git add supabase/functions/notify-settlement/index.ts xBill/Services/ExpenseService.swift xBill/ViewModels/GroupViewModel.swift
git commit -m "notify-settlement derives parties from the settlement row"
```

---

## Task 10: Verification and deployment gate

**Files:**
- Modify: `CLAUDE.md`, `AUDIT_REPORT.md`

- [ ] **Step 1: Full unit suite**

```bash
scripts/run-coverage.sh unit
```
Expected: all pass, zero failures, zero skips. Record the count.

- [ ] **Step 2: Release build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project xBill.xcodeproj -scheme xBill -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: STOP — deployment gate**

Report to the user, and do not continue without an explicit yes:

1. `supabase db query --linked` output showing current per-user balances
2. The backfill row count (expected 2)
3. The exact commands that would run:

```bash
supabase db push --linked
supabase functions deploy notify-settlement
```

**Nothing is applied to the live database or Edge Functions without that approval.**

- [ ] **Step 4: After approval — deploy and verify**

```bash
supabase db push --linked
supabase db query --file scripts/verify-settlements-backfill.sql --linked   # expect ZERO rows
supabase functions deploy notify-settlement
```

If the verification query returns any row, **stop and report**. Balances changed; do not
proceed to the device.

- [ ] **Step 5: Device verification**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme xBill -project xBill.xcodeproj -destination 'id=00008140-000135EE3432801C' -configuration Debug -allowProvisioningUpdates build
APP=$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme xBill -project xBill.xcodeproj -destination 'id=00008140-000135EE3432801C' -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
xcrun devicectl device install app --device 00008140-000135EE3432801C "$APP/xBill.app"
```

Ask the user to: record a payment **as the creditor** — the path that silently failed before —
confirm it appears in Recent Payments with their name, confirm the balance moved, then delete
it and confirm the balance returns. Pull the log afterwards:

```bash
xcrun devicectl device copy from --device 00008140-000135EE3432801C \
  --domain-type appDataContainer --domain-identifier com.vijaygoyal.xbill \
  --source Documents/xbill-diagnostics.log --destination ./diagnostics/2026-07-28-settlements/after.log
```

- [ ] **Step 6: Update docs and commit**

- `CLAUDE.md`: fix-log entry; File Map entries for the four new files; update the Settle Up
  trap-index row now that the RLS and the UI agree.
- `AUDIT_REPORT.md`: mark `REV-01` ✅ Fixed, and `REV-02` / `REV-13` as structurally removed.
- `diagnostics/README.md`: append an index row for the device evidence.

```bash
git add -A && git commit -m "Settlements ledger: verification and docs" && git push
```

---

## Self-Review

**Spec coverage.** §3 data model → Tasks 1, 3. §4 balance computation → Task 2, wired in
Task 5. §5 UI → Tasks 6, 7, 8; the `notify-settlement` sub-section → Task 9. §6 migration and
backfill → Tasks 3 and 10. §7 out of scope → nothing planned for IOUs, cross-group settling,
payment editing, notes/backdating, or dropping `is_settled`. §8 testing → Tasks 1, 2, 5 (unit),
Task 10 steps 4–5 (backfill and device). §9 success criteria → all five map to Task 10.

**Placeholders.** None. Every code step carries the code.

**Type consistency.** `Settlement` fields are identical across Tasks 1, 2, 4, 5, 7.
`recordPayment(from:to:amount:)` and `deletePayment(_:)` match between Tasks 5 and 7.
`SettlementDataProviding`'s three methods match between Tasks 4 and 5.
`settlementSuggestions(expenses:splits:settlements:names:currency:)` matches between Tasks 2
and 5. `SettlementInsert` is defined in Task 4 and used only there.

**Known ordering hazard.** Tasks 4–9 will not run correctly against production until Task 10
deploys migration 041 — the app compiles and its unit tests pass, but `fetchSettlements` will
404 on a live device. Do not attempt device testing before Task 10 step 4.

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

// MARK: - Backfill equivalence

/// The claim migration 041's deployment rests on: replacing `splits.is_settled` with a
/// settlements ledger changes nobody's balance.
///
/// Design spec §8 requires this to be green before anything touches production. Until now the
/// claim rested entirely on one SQL script — a script that was wrong once already (it
/// aggregated after a FULL OUTER JOIN on a non-unique key and could mask a real drift), and
/// which until this round could only be run after the point of no return.
///
/// This suite states the same identity in Swift, against the production balance function:
///
///   netBalances(all splits, minus backfilled settlements) == netBalances(unsettled splits only)
///
/// The left side is the new model. The right side is the old one — `netBalances` used to skip
/// settled splits, so passing it only the unsettled ones reproduces its former behaviour
/// exactly. `applyBackfillRule` is a line-for-line transcription of the migration's WHERE
/// clause, so a change to either has to be made in both places to keep this green.
@Suite("Backfill equivalence")
@MainActor
struct BackfillEquivalenceTests {

    /// `WHERE s.is_settled AND e.paid_by IS NOT NULL AND e.paid_by <> s.user_id AND s.amount > 0`,
    /// projected to `(group, debtor -> payer, amount)`. Same rule as 041_settlements.sql.
    private func applyBackfillRule(expenses: [Expense], splits: [UUID: [Split]]) -> [Settlement] {
        expenses.flatMap { expense -> [Settlement] in
            guard let payerID = expense.payerID else { return [] }
            return (splits[expense.id] ?? []).compactMap { split in
                guard split.isSettled, split.userID != payerID, split.amount > 0 else { return nil }
                return Settlement(id: UUID(), groupID: expense.groupID,
                                  fromUserID: split.userID, toUserID: payerID,
                                  amount: split.amount, currency: expense.currency,
                                  recordedBy: split.userID, createdAt: Date())
            }
        }
    }

    private func makeSplit(_ expenseID: UUID, _ userID: UUID, _ amount: Decimal,
                           settled: Bool) -> Split {
        Split(id: UUID(), expenseID: expenseID, userID: userID, amount: amount,
              isSettled: settled, settledAt: settled ? Date() : nil)
    }

    private func makeExpense(group: UUID, payer: UUID?, amount: Decimal) -> Expense {
        Expense(id: UUID(), groupID: group, title: "Expense", amount: amount, currency: "USD",
                payerID: payer, category: .food, notes: nil, receiptURL: nil,
                originalAmount: nil, originalCurrency: nil, recurrence: .none,
                nextOccurrenceDate: nil, createdAt: Date())
    }

    /// Old model: what `netBalances` computed before this branch — settled splits skipped, no
    /// ledger. Reproduced by handing it only the unsettled splits.
    private func oldModelBalances(expenses: [Expense], splits: [UUID: [Split]]) -> [UUID: Decimal] {
        let unsettled = splits.mapValues { $0.filter { !$0.isSettled } }
        return SplitCalculator.netBalances(expenses: expenses, splits: unsettled, settlements: [])
    }

    /// Fixture covering every branch of the backfill's WHERE clause, plus the cases the
    /// production data actually contains. Returns the expected number of backfill rows so the
    /// test also pins *which* splits the rule selects, not only that the totals agree.
    private func fixture() -> (expenses: [Expense], splits: [UUID: [Split]],
                               members: [UUID], expectedBackfillRows: Int) {
        let group = UUID()
        let alice = UUID(), bob = UUID(), carol = UUID()

        // 1. Mixed: one settled non-payer share, one unsettled, plus the payer's own share.
        //    The payer's share is skipped by netBalances and excluded by the migration's
        //    `e.paid_by <> s.user_id` — backfilling it would violate settlements_distinct_parties.
        //    This is the shape 5 of production's 7 settled splits actually have.
        let mixed = makeExpense(group: group, payer: alice, amount: 30)
        let mixedSplits = [
            makeSplit(mixed.id, alice, 10, settled: true),   // payer's own: not a backfill row
            makeSplit(mixed.id, bob,   10, settled: true),   // backfill row
            makeSplit(mixed.id, carol, 10, settled: false)
        ]

        // 2. Fully settled: every non-payer share repaid. Both models must report zero for the
        //    debtors and zero net for the payer from this expense.
        let settled = makeExpense(group: group, payer: bob, amount: 24)
        let settledSplits = [
            makeSplit(settled.id, bob,   8, settled: true),
            makeSplit(settled.id, alice, 8, settled: true),  // backfill row
            makeSplit(settled.id, carol, 8, settled: true)   // backfill row
        ]

        // 3. Nothing settled: the ordinary case, no backfill rows at all.
        let open = makeExpense(group: group, payer: carol, amount: 15)
        let openSplits = [
            makeSplit(open.id, carol, 5, settled: false),
            makeSplit(open.id, alice, 5, settled: false),
            makeSplit(open.id, bob,   5, settled: false)
        ]

        // 4. Orphaned payer (migration 017 set expenses.paid_by ON DELETE SET NULL). Contributes
        //    nothing under either model; `e.paid_by IS NOT NULL` excludes it from the backfill.
        let orphan = makeExpense(group: group, payer: nil, amount: 12)
        let orphanSplits = [
            makeSplit(orphan.id, alice, 6, settled: true),
            makeSplit(orphan.id, bob,   6, settled: false)
        ]

        // 5. Zero-amount settled share (I5). `splits` permits 0.00 via CHECK (amount >= 0);
        //    `settlements` requires amount > 0, so a backfill row here would abort the whole
        //    migration. It contributes 0 under both models, so excluding it is free.
        let zero = makeExpense(group: group, payer: alice, amount: 9)
        let zeroSplits = [
            makeSplit(zero.id, alice, 9, settled: false),
            makeSplit(zero.id, bob,   0, settled: true)      // excluded: amount is not > 0
        ]

        // 6. Uneven shares with a sub-cent-free remainder, so rounding is exercised on both
        //    sides rather than only on round numbers.
        let uneven = makeExpense(group: group, payer: carol, amount: 20)
        let unevenSplits = [
            makeSplit(uneven.id, carol, Decimal(string: "6.66")!, settled: false),
            makeSplit(uneven.id, alice, Decimal(string: "6.67")!, settled: true),  // backfill row
            makeSplit(uneven.id, bob,   Decimal(string: "6.67")!, settled: false)
        ]

        let expenses = [mixed, settled, open, orphan, zero, uneven]
        let splits: [UUID: [Split]] = [
            mixed.id: mixedSplits, settled.id: settledSplits, open.id: openSplits,
            orphan.id: orphanSplits, zero.id: zeroSplits, uneven.id: unevenSplits
        ]
        return (expenses, splits, [alice, bob, carol], 4)
    }

    @Test("The backfill leaves every per-user balance unchanged")
    func backfillPreservesBalances() {
        let (expenses, splits, members, expectedRows) = fixture()

        let backfill = applyBackfillRule(expenses: expenses, splits: splits)
        #expect(backfill.count == expectedRows)

        let old = oldModelBalances(expenses: expenses, splits: splits)
        let new = SplitCalculator.netBalances(expenses: expenses, splits: splits,
                                              settlements: backfill)

        // Compare over the union of both key sets, not just one — a user present in only one
        // model is exactly the drift this is looking for.
        for user in Set(old.keys).union(new.keys) {
            #expect(old[user, default: .zero] == new[user, default: .zero],
                    "Balance drift for \(user): old \(old[user, default: .zero]) vs new \(new[user, default: .zero])")
        }
        // And every seeded member is actually represented, so an all-empty run cannot pass.
        for member in members {
            #expect(new[member] != nil)
        }
        // Balances must still sum to zero: money is only moved between members, never created.
        #expect(new.values.reduce(Decimal.zero, +) == .zero)
    }

    @Test("Every backfill row is one the database would accept")
    func backfillRowsSatisfyTheTableConstraints() {
        let (expenses, splits, _, _) = fixture()
        let backfill = applyBackfillRule(expenses: expenses, splits: splits)

        for row in backfill {
            // settlements_distinct_parties
            #expect(row.fromUserID != row.toUserID)
            // CHECK (amount > 0)
            #expect(row.amount > 0)
        }
    }

    @Test("Dropping the zero-amount guard would produce a row the CHECK rejects")
    func zeroAmountGuardIsLoadBearing() {
        // Proves the fixture really contains the I5 case and that `s.amount > 0` is what keeps
        // it out — without this, the guard could be deleted from the migration and every other
        // assertion here would still pass.
        let (expenses, splits, _, _) = fixture()

        let withoutGuard = expenses.flatMap { expense -> [Settlement] in
            guard let payerID = expense.payerID else { return [] }
            return (splits[expense.id] ?? []).compactMap { split in
                guard split.isSettled, split.userID != payerID else { return nil }
                return Settlement(id: UUID(), groupID: expense.groupID,
                                  fromUserID: split.userID, toUserID: payerID,
                                  amount: split.amount, currency: expense.currency,
                                  recordedBy: split.userID, createdAt: Date())
            }
        }

        #expect(withoutGuard.contains { $0.amount == 0 })
        #expect(withoutGuard.count == applyBackfillRule(expenses: expenses, splits: splits).count + 1)
    }
}

// MARK: - Record Payment prefill

@Suite("Record Payment amount prefill")
struct RecordPaymentPrefillTests {

    /// The sheet prefilled via `NSDecimalNumber.stringValue`, which drops trailing zeros, so an
    /// $8.00 debt showed as "8". Same behaviour that made PayPal.Me ignore a settlement amount
    /// (`95USD` rather than `95.00USD`) — see `PaymentLinkService.formattedAmount`.
    @Test("A whole-dollar amount prefills with two decimals")
    func wholeAmountKeepsTwoDecimals() {
        #expect(PaymentLinkService.formattedAmount(Decimal(8)) == "8.00")
        #expect(PaymentLinkService.formattedAmount(Decimal(string: "7")!) == "7.00")
    }

    @Test("A fractional amount is unchanged")
    func fractionalAmountIsExact() {
        #expect(PaymentLinkService.formattedAmount(Decimal(string: "15.50")!) == "15.50")
        #expect(PaymentLinkService.formattedAmount(Decimal(string: "0.20")!) == "0.20")
    }

    /// The prefill is fed straight back into the sheet's own parser, so it must not contain a
    /// grouping separator — `Decimal(string:locale:)` would reject "1,234.50".
    @Test("A four-figure prefill round-trips through the sheet's parser")
    func largeAmountRoundTrips() {
        let text = PaymentLinkService.formattedAmount(Decimal(string: "1234.50")!)
        #expect(!text.contains(","))
        #expect(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) == Decimal(string: "1234.50"))
    }
}

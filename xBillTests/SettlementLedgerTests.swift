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

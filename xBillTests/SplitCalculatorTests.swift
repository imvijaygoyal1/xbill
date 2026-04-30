import Testing
import Foundation
@testable import xBill

// MARK: - SplitCalculatorTests

@Suite("SplitCalculator")
struct SplitCalculatorTests {

    // MARK: - Helpers

    private func makeInputs(count: Int) -> [SplitInput] {
        (0..<count).map { i in
            SplitInput(userID: UUID(), displayName: "Person \(i + 1)")
        }
    }

    // MARK: - Equal Split

    @Test("Equal split divides total evenly")
    func equalSplitEven() {
        var inputs = makeInputs(count: 3)
        SplitCalculator.splitEqually(total: 90.00, inputs: &inputs)

        let amounts = inputs.map(\.amount)
        #expect(amounts.allSatisfy { $0 == 30.00 })
        #expect(amounts.reduce(.zero, +) == 90.00)
    }

    @Test("Equal split handles rounding remainder")
    func equalSplitRounding() {
        var inputs = makeInputs(count: 3)
        SplitCalculator.splitEqually(total: 10.00, inputs: &inputs)

        let total = inputs.map(\.amount).reduce(Decimal.zero, +)
        #expect(total == 10.00)
    }

    @Test("Equal split ignores excluded participants")
    func equalSplitExcluded() {
        var inputs = makeInputs(count: 4)
        inputs[2].isIncluded = false
        inputs[3].isIncluded = false

        SplitCalculator.splitEqually(total: 50.00, inputs: &inputs)

        #expect(inputs[0].amount == 25.00)
        #expect(inputs[1].amount == 25.00)
        #expect(inputs[2].amount == .zero)
        #expect(inputs[3].amount == .zero)
    }

    @Test("Equal split with single participant assigns full amount")
    func equalSplitSingle() {
        var inputs = makeInputs(count: 1)
        SplitCalculator.splitEqually(total: 42.99, inputs: &inputs)

        #expect(inputs[0].amount == 42.99)
    }

    // MARK: - Percentage Split

    @Test("Percentage split distributes proportionally")
    func percentageSplit() {
        var inputs = makeInputs(count: 2)
        inputs[0].percentage = 60
        inputs[1].percentage = 40

        SplitCalculator.splitByPercentage(total: 100.00, inputs: &inputs)

        #expect(inputs[0].amount == 60.00)
        #expect(inputs[1].amount == 40.00)
        #expect(inputs.map(\.amount).reduce(.zero, +) == 100.00)
    }

    @Test("Percentage split absorbs rounding error in first participant")
    func percentageSplitRounding() {
        var inputs = makeInputs(count: 3)
        inputs[0].percentage = 33
        inputs[1].percentage = 33
        inputs[2].percentage = 34

        SplitCalculator.splitByPercentage(total: 10.00, inputs: &inputs)

        let total = inputs.map(\.amount).reduce(Decimal.zero, +)
        #expect(total == 10.00)
    }

    // MARK: - Exact Split Validation

    @Test("Exact validation passes when amounts sum correctly")
    func exactValidationPass() {
        var inputs = makeInputs(count: 2)
        inputs[0].amount = 30.00
        inputs[1].amount = 20.00

        let error = SplitCalculator.validateExact(total: 50.00, inputs: inputs)
        #expect(error == nil)
    }

    @Test("Exact validation fails when amounts don't match total")
    func exactValidationFail() {
        var inputs = makeInputs(count: 2)
        inputs[0].amount = 20.00
        inputs[1].amount = 20.00

        let error = SplitCalculator.validateExact(total: 50.00, inputs: inputs)
        #expect(error != nil)
    }

    // MARK: - Net Balances

    @Test("Net balances: payer is credited per participant split, payer's own split skipped")
    func netBalances() {
        let payerID = UUID()
        let participant1 = UUID()
        let participant2 = UUID()

        let expense = Expense(
            id: UUID(), groupID: UUID(), title: "Dinner",
            amount: 60.00, currency: "USD", payerID: payerID,
            category: .food, notes: nil, receiptURL: nil,
            recurrence: .none, createdAt: Date())
        let splits: [UUID: [Split]] = [
            expense.id: [
                // Payer's own split is skipped by the algorithm
                Split(id: UUID(), expenseID: expense.id, userID: payerID,      amount: 20.00, percentage: nil, isSettled: false, settledAt: nil),
                Split(id: UUID(), expenseID: expense.id, userID: participant1, amount: 20.00, percentage: nil, isSettled: false, settledAt: nil),
                Split(id: UUID(), expenseID: expense.id, userID: participant2, amount: 20.00, percentage: nil, isSettled: false, settledAt: nil),
            ]
        ]

        let balances = SplitCalculator.netBalances(expenses: [expense], splits: splits)

        // Payer credited +20 per unsettled non-payer split (2 × $20 = $40)
        #expect(balances[payerID]      == 40.00)
        #expect(balances[participant1] == -20.00)
        #expect(balances[participant2] == -20.00)
    }

    // MARK: - Minimize Transactions

    @Test("Minimize transactions produces correct settlements")
    func minimizeTransactions() {
        let aliceID = UUID()
        let bobID   = UUID()
        let charlieID = UUID()

        let balances: [UUID: Decimal] = [
            aliceID:   30.00,   // Alice is owed 30
            bobID:    -10.00,   // Bob owes 10
            charlieID: -20.00,  // Charlie owes 20
        ]
        let names: [UUID: String] = [
            aliceID: "Alice", bobID: "Bob", charlieID: "Charlie"
        ]

        let suggestions = SplitCalculator.minimizeTransactions(
            balances: balances,
            names: names,
            currency: "USD"
        )

        let totalTransferred = suggestions.map(\.amount).reduce(.zero, +)
        #expect(totalTransferred == 30.00)
        #expect(suggestions.count <= 2)
    }

    @Test("Minimize transactions returns empty when all settled")
    func minimizeTransactionsAllSettled() {
        let suggestions = SplitCalculator.minimizeTransactions(
            balances: [:],
            names: [:],
            currency: "USD"
        )
        #expect(suggestions.isEmpty)
    }

    // MARK: - Single Payer

    @Test("Single payer: one person paid, two others owe equal shares")
    func singlePayer() {
        let payerID = UUID()
        let p1 = UUID()
        let p2 = UUID()

        let expense = Expense(
            id: UUID(), groupID: UUID(), title: "Groceries",
            amount: 90.00, currency: "USD", payerID: payerID,
            category: .food, notes: nil, receiptURL: nil,
            recurrence: .none, createdAt: Date())
        let splits: [UUID: [Split]] = [
            expense.id: [
                Split(id: UUID(), expenseID: expense.id, userID: payerID, amount: 30.00, percentage: nil, isSettled: false, settledAt: nil),
                Split(id: UUID(), expenseID: expense.id, userID: p1,      amount: 30.00, percentage: nil, isSettled: false, settledAt: nil),
                Split(id: UUID(), expenseID: expense.id, userID: p2,      amount: 30.00, percentage: nil, isSettled: false, settledAt: nil),
            ]
        ]

        let balances = SplitCalculator.netBalances(expenses: [expense], splits: splits)
        // Payer credited 2 × $30 = $60
        #expect(balances[payerID] == 60.00)
        #expect(balances[p1]      == -30.00)
        #expect(balances[p2]      == -30.00)

        let names = [payerID: "Payer", p1: "P1", p2: "P2"]
        let suggestions = SplitCalculator.minimizeTransactions(
            balances: balances, names: names, currency: "USD"
        )
        // Exactly 2 transfers: P1→Payer $30, P2→Payer $30
        #expect(suggestions.count == 2)
        #expect(suggestions.map { $0.amount }.reduce(Decimal.zero, +) == 60.00)
        #expect(suggestions.allSatisfy { $0.toUserID == payerID })
    }

    // MARK: - Circular Debt

    @Test("Circular debt: net balances cancel to zero, no transfers needed")
    func circularDebt() {
        // A paid for B, B paid for C, C paid for A — equal amounts cancel out
        let aID = UUID(), bID = UUID(), cID = UUID()

        let eA = Expense(id: UUID(), groupID: UUID(), title: "A→B",
                         amount: 10.00, currency: "USD", payerID: aID,
                         category: .other, notes: nil, receiptURL: nil,
                         recurrence: .none, createdAt: Date())
        let eB = Expense(id: UUID(), groupID: UUID(), title: "B→C",
                         amount: 10.00, currency: "USD", payerID: bID,
                         category: .other, notes: nil, receiptURL: nil,
                         recurrence: .none, createdAt: Date())
        let eC = Expense(id: UUID(), groupID: UUID(), title: "C→A",
                         amount: 10.00, currency: "USD", payerID: cID,
                         category: .other, notes: nil, receiptURL: nil,
                         recurrence: .none, createdAt: Date())

        let splits: [UUID: [Split]] = [
            eA.id: [Split(id: UUID(), expenseID: eA.id, userID: bID, amount: 10.00, percentage: nil, isSettled: false, settledAt: nil)],
            eB.id: [Split(id: UUID(), expenseID: eB.id, userID: cID, amount: 10.00, percentage: nil, isSettled: false, settledAt: nil)],
            eC.id: [Split(id: UUID(), expenseID: eC.id, userID: aID, amount: 10.00, percentage: nil, isSettled: false, settledAt: nil)],
        ]

        let balances = SplitCalculator.netBalances(expenses: [eA, eB, eC], splits: splits)
        // Each person is owed $10 and owes $10 → net 0
        #expect(balances[aID] ?? .zero == .zero)
        #expect(balances[bID] ?? .zero == .zero)
        #expect(balances[cID] ?? .zero == .zero)

        let names = [aID: "Alice", bID: "Bob", cID: "Charlie"]
        let suggestions = SplitCalculator.minimizeTransactions(
            balances: balances, names: names, currency: "USD"
        )
        #expect(suggestions.isEmpty)
    }

    // MARK: - Partially Settled

    @Test("Partially settled: settled splits are excluded from net balances")
    func partiallySeltled() {
        let payerID = UUID()
        let p1 = UUID()   // already settled
        let p2 = UUID()   // still owes

        let expense = Expense(
            id: UUID(), groupID: UUID(), title: "Hotel",
            amount: 90.00, currency: "USD", payerID: payerID,
            category: .accommodation, notes: nil, receiptURL: nil,
            recurrence: .none, createdAt: Date())
        let splits: [UUID: [Split]] = [
            expense.id: [
                Split(id: UUID(), expenseID: expense.id, userID: payerID, amount: 30.00, percentage: nil, isSettled: false, settledAt: nil),
                Split(id: UUID(), expenseID: expense.id, userID: p1,      amount: 30.00, percentage: nil, isSettled: true,  settledAt: Date()),
                Split(id: UUID(), expenseID: expense.id, userID: p2,      amount: 30.00, percentage: nil, isSettled: false, settledAt: nil),
            ]
        ]

        let balances = SplitCalculator.netBalances(expenses: [expense], splits: splits)
        // Only p2's unsettled $30 affects balances
        #expect(balances[payerID] == 30.00)
        #expect(balances[p1]      == nil)      // settled — no outstanding balance
        #expect(balances[p2]      == -30.00)

        let names = [payerID: "Payer", p1: "P1", p2: "P2"]
        let suggestions = SplitCalculator.minimizeTransactions(
            balances: balances, names: names, currency: "USD"
        )
        #expect(suggestions.count == 1)
        #expect(suggestions[0].amount == 30.00)
        #expect(suggestions[0].fromUserID == p2)
        #expect(suggestions[0].toUserID   == payerID)
    }

    // MARK: - Two People

    @Test("Two people: one transfer to settle")
    func twoPeople() {
        let aliceID = UUID()
        let bobID   = UUID()

        let expense = Expense(
            id: UUID(), groupID: UUID(), title: "Taxi",
            amount: 40.00, currency: "USD", payerID: aliceID,
            category: .transport, notes: nil, receiptURL: nil,
            recurrence: .none, createdAt: Date())
        let splits: [UUID: [Split]] = [
            expense.id: [
                Split(id: UUID(), expenseID: expense.id, userID: aliceID, amount: 20.00, percentage: nil, isSettled: false, settledAt: nil),
                Split(id: UUID(), expenseID: expense.id, userID: bobID,   amount: 20.00, percentage: nil, isSettled: false, settledAt: nil),
            ]
        ]

        let balances = SplitCalculator.netBalances(expenses: [expense], splits: splits)
        #expect(balances[aliceID] == 20.00)
        #expect(balances[bobID]   == -20.00)

        let suggestions = SplitCalculator.minimizeTransactions(
            balances: balances,
            names: [aliceID: "Alice", bobID: "Bob"],
            currency: "USD"
        )
        #expect(suggestions.count == 1)
        #expect(suggestions[0].amount == 20.00)
        #expect(suggestions[0].fromUserID == bobID)
        #expect(suggestions[0].toUserID   == aliceID)
    }

    // MARK: - Floating Point Precision

    @Test("Floating point: $10 split 3 ways sums exactly to $10.00")
    func floatingPointPrecision() {
        var inputs = makeInputs(count: 3)
        SplitCalculator.splitEqually(total: 10.00, inputs: &inputs)

        let amounts = inputs.map(\.amount)
        let sum = amounts.reduce(Decimal.zero, +)

        // Sum must be exactly 10.00 — no floating point drift
        #expect(sum == 10.00)

        // Two shares are equal, one absorbs the remainder
        let distinct = Set(amounts.map { "\($0)" })
        #expect(distinct.count <= 2)

        // Each individual share is either $3.33 or $3.34
        #expect(amounts.allSatisfy { $0 >= 3.33 && $0 <= 3.34 })
    }

    @Test("Floating point: $1 split 3 ways — no penny is lost or doubled")
    func floatingPointPrecisionSmall() {
        var inputs = makeInputs(count: 3)
        SplitCalculator.splitEqually(total: 1.00, inputs: &inputs)

        #expect(inputs.map(\.amount).reduce(.zero, +) == 1.00)
        #expect(inputs.allSatisfy { $0.amount >= Decimal(string: "0.33")! && $0.amount <= Decimal(string: "0.34")! })
    }
}

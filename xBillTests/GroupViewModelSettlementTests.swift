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

    @Test("Recording the same payment twice in a row does not double-credit it")
    func repeatedSequentialPaymentIsIgnored() async {
        // IMP-4: the settle-up confirmation and the post-handoff "did you complete this
        // payment?" alert can both call recordPayment for the same debt, one fully finishing
        // before the other starts — sequential, not concurrent, so `isLoading` alone cannot
        // catch it.
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
        await vm.recordPayment(from: bob, to: alice, amount: 10)

        #expect(settlements.stored.count == 1)
        #expect(vm.settlements.count == 1)
        #expect(vm.balance(for: bob) == 0)
    }

    @Test("A failed insert surfaces an error and records nothing")
    func failedInsertIsReported() async {
        let group = makeGroup(); let alice = UUID(); let bob = UUID()
        let expenses = FakeExpenseService(); let settlements = FakeSettlementService()
        let e = Expense(id: UUID(), groupID: group.id, title: "Dinner", amount: 30,
                        currency: "USD", payerID: alice, category: .food, notes: nil,
                        receiptURL: nil, originalAmount: nil, originalCurrency: nil,
                        recurrence: .none, nextOccurrenceDate: nil, createdAt: Date())
        expenses.expenses = [e]
        expenses.splits = [Split(id: UUID(), expenseID: e.id, userID: bob, amount: 10,
                                 isSettled: false, settledAt: nil)]
        settlements.insertError = AppError.permissionDenied

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: expenses,
                                settlementService: settlements,
                                currentUserIDProvider: { bob })
        await vm.load(showError: false)
        #expect(vm.balance(for: bob) == -10)

        await vm.recordPayment(from: bob, to: alice, amount: 10)

        #expect(settlements.stored.isEmpty)
        #expect(vm.errorAlert != nil)
        // What the user actually experiences: the ledger and the visible balance are both
        // untouched by a write that never committed.
        #expect(vm.settlements.isEmpty)
        #expect(vm.balance(for: bob) == -10)
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

    @Test("A failed delete rolls the payment back")
    func failedDeleteRollsBack() async {
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
        settlements.deleteError = AppError.permissionDenied

        await vm.deletePayment(payment)

        // The optimistic local removal must be rolled back: the payment is still recorded,
        // the balance still reflects it, and the user is told the delete did not go through —
        // the riskiest branch of deletePayment (mutate, server rejects, restore).
        #expect(vm.settlements.contains { $0.id == payment.id })
        #expect(vm.balance(for: bob) == 0)
        #expect(vm.errorAlert != nil)
    }
}

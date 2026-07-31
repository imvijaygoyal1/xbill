import Foundation
import Testing
@testable import xBill

@MainActor
final class FakeSettlementService: SettlementDataProviding {
    var stored: [Settlement] = []
    var insertError: Error?
    var deleteError: Error?
    /// When set, `deleteSettlement` removes the row from `stored` and *then* throws — the
    /// commit-but-error case: a request that landed on the server while the client saw a
    /// timeout, a dropped response, or a 500 raised after the write. Distinct from
    /// `deleteError`, which throws before touching `stored`.
    var deleteErrorAfterCommit: Error?
    var deletedIDs: [UUID] = []
    /// When set, `fetchSettlements` captures its return value *before* sleeping — modelling a
    /// server read that started before a concurrent write committed, the IMP-1 race.
    var fetchDelay: Duration?
    /// When set, `deleteSettlement` sleeps before failing — gives a concurrent `recordPayment`
    /// room to land while the delete is still in flight, for the IMP-1/deletePayment rollback
    /// scoping tests.
    var deleteDelay: Duration?
    /// Ordered log of call boundaries. A timing test that only asserts final state cannot tell
    /// a genuine interleaving from a scheduling accident where the two operations happened to
    /// run back-to-back — this is what lets a test assert the interleaving actually occurred.
    var events: [String] = []

    func fetchSettlements(groupID: UUID) async throws -> [Settlement] {
        events.append("fetch.start")
        let snapshot = stored
        if let fetchDelay { try? await Task.sleep(for: fetchDelay) }
        events.append("fetch.end")
        return snapshot
    }

    func recordSettlement(groupID: UUID, fromUserID: UUID, toUserID: UUID,
                          amount: Decimal, currency: String, recordedBy: UUID) async throws -> Settlement {
        if let insertError { throw insertError }
        let s = Settlement(id: UUID(), groupID: groupID, fromUserID: fromUserID,
                           toUserID: toUserID, amount: amount, currency: currency,
                           recordedBy: recordedBy, createdAt: Date())
        stored.append(s)
        events.append("record")
        return s
    }

    func deleteSettlement(id: UUID) async throws {
        events.append("delete.start")
        if let deleteDelay { try? await Task.sleep(for: deleteDelay) }
        if let deleteError {
            events.append("delete.failed")
            throw deleteError
        }
        deletedIDs.append(id)
        stored.removeAll { $0.id == id }
        if let deleteErrorAfterCommit {
            events.append("delete.committedThenFailed")
            throw deleteErrorAfterCommit
        }
        events.append("delete.end")
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

    @Test("A payment recorded while a load is in flight is not lost")
    func paymentSurvivesConcurrentLoad() async {
        // IMP-1 (round 2, Critical): recordPayment no longer blocks on isLoading, and load()'s
        // settlements fetch can therefore return a snapshot captured *before* this insert
        // committed. That must not overwrite the just-recorded payment when load() applies it.
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
        settlements.events = []

        // Arm a settlements fetch that snapshots `stored` now (empty) and only returns after
        // the payment below has been recorded — simulating a read that started first but
        // resolved second.
        settlements.fetchDelay = .milliseconds(60)
        let loadTask = Task { await vm.load(showError: false) }
        try? await Task.sleep(for: .milliseconds(15))

        await vm.recordPayment(from: bob, to: alice, amount: 10)
        #expect(vm.balance(for: bob) == 0)

        await loadTask.value

        // The stale-snapshot load must not have wiped the payment back out.
        #expect(vm.settlements.count == 1)
        #expect(vm.balance(for: bob) == 0)
        // Prove the fetch's snapshot really was taken before the record and returned after —
        // i.e. genuine interleaving, not the two operations happening to run back-to-back
        // (which the final-state assertions above could not distinguish from this).
        #expect(settlements.events == ["fetch.start", "record", "fetch.end"])
    }

    @Test("deletePayment's rollback does not drop a concurrently-recorded payment")
    func deleteRollbackDoesNotDropConcurrentPayment() async {
        // IMP-1/deletePayment (round 2, Important): a failed delete used to restore a whole
        // `settlements` snapshot captured before its optimistic removal — reverting any
        // payment recorded while the delete was in flight, even though that write committed
        // and has nothing to do with this delete.
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
        await vm.recordPayment(from: bob, to: alice, amount: 5)
        let p1 = try! #require(vm.settlements.first)
        settlements.events = []

        settlements.deleteError = AppError.permissionDenied
        settlements.deleteDelay = .milliseconds(80)
        let deleteTask = Task { await vm.deletePayment(p1) }
        try? await Task.sleep(for: .milliseconds(20))

        // A different amount so this does not collide with the IMP-4 duplicate window.
        await vm.recordPayment(from: bob, to: alice, amount: 2)

        await deleteTask.value

        // p1's failed delete must be rolled back, and p2 (recorded while the delete was still
        // in flight) must still be there — a snapshot rollback would have dropped it.
        #expect(vm.settlements.contains { $0.id == p1.id })
        #expect(vm.settlements.contains { $0.amount == 2 })
        #expect(vm.settlements.count == 2)
        // Prove the record genuinely landed while the delete was still in flight, not before
        // it started or after it had already failed.
        #expect(settlements.events == ["delete.start", "record", "delete.failed"])
    }

    @Test("Deleting a payment then immediately re-recording it is allowed")
    func deleteThenReRecordIsAllowed() async {
        // IMP-4 follow-up: the duplicate window must not block a deliberate correction —
        // delete a payment, then re-record the exact same amount right away.
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

        await vm.recordPayment(from: bob, to: alice, amount: 5)
        let p1 = try! #require(vm.settlements.first)
        await vm.deletePayment(p1)

        await vm.recordPayment(from: bob, to: alice, amount: 5)

        #expect(vm.settlements.count == 1)
        #expect(settlements.stored.count == 1)
        #expect(vm.errorAlert == nil)
    }

    @Test("A fetch that omits a previously-returned settlement removes it locally")
    func fetchOmissionRemovesSettlement() async {
        // The round-3 Critical (REV-03 reproduced on money): a settlement that was never
        // recorded through *this* VM's recordPayment — e.g. another member's payment, seen on
        // an earlier load — must be able to leave `vm.settlements` once a later fetch stops
        // returning it (they deleted it, or this device's earlier read was stale). The old
        // merge kept every local row a fetch omitted, with no way for one to ever be dropped;
        // this settlement is deliberately never touched by recordPayment/deletePayment so this
        // test exercises only the fetch-merge path, not the pending-map path the other tests
        // already cover.
        let group = makeGroup(); let alice = UUID(); let bob = UUID()
        let expenses = FakeExpenseService(); let settlements = FakeSettlementService()
        let otherMembersPayment = Settlement(id: UUID(), groupID: group.id, fromUserID: bob,
                                             toUserID: alice, amount: 5, currency: "USD",
                                             recordedBy: alice, createdAt: Date())
        settlements.stored = [otherMembersPayment]

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: expenses, settlementService: settlements,
                                currentUserIDProvider: { bob })
        await vm.load(showError: false)
        #expect(vm.settlements.contains { $0.id == otherMembersPayment.id })

        // Simulate the row being deleted elsewhere — by another member, on another device —
        // which this VM never observes directly. The next fetch simply stops returning it.
        settlements.stored.removeAll { $0.id == otherMembersPayment.id }
        await vm.load(showError: false)

        // Round 4: it was the group's only settlement, so that fetch came back empty, and an
        // empty settlements response is now refused once before it is believed — see
        // emptyFetchIsRefusedOnceThenTrusted. The row is held one more refresh, under the
        // stale-balance warning, rather than being dropped on a possibly-stale read.
        #expect(vm.settlements.count == 1)
        #expect(vm.balanceLoadFailed)

        await vm.load(showError: false)

        #expect(vm.settlements.isEmpty)
    }

    @Test("A delete that commits and then reports failure is cleared by the next fetch")
    func committedDeleteReportedAsFailureIsNotPinnedForever() async {
        // The round-4 Important. `deletePayment`'s catch runs whenever the *client* sees an
        // error, which includes a request that reached the server and committed — a timeout, a
        // dropped response, a 500 raised after the write. The row is genuinely gone, so every
        // later fetch omits it. Before generation expiry, the catch re-pinned it with nothing
        // able to ever remove the pin, permanently crediting a payment the ledger did not
        // contain; and a user retry could not clear it either, because deleting an
        // already-deleted row affects zero rows and `SupabaseWrite.requireAffected` (correctly)
        // reports that as a failure, landing straight back on the same re-pin.
        let group = makeGroup(); let alice = UUID(); let bob = UUID(); let carol = UUID()
        let expenses = FakeExpenseService(); let settlements = FakeSettlementService()
        let e = Expense(id: UUID(), groupID: group.id, title: "Dinner", amount: 30,
                        currency: "USD", payerID: alice, category: .food, notes: nil,
                        receiptURL: nil, originalAmount: nil, originalCurrency: nil,
                        recurrence: .none, nextOccurrenceDate: nil, createdAt: Date())
        expenses.expenses = [e]
        expenses.splits = [Split(id: UUID(), expenseID: e.id, userID: bob, amount: 10,
                                 isSettled: false, settledAt: nil)]
        // An unrelated payment between two other members, so the reconciling fetch below is not
        // empty. The empty-fetch case is covered separately by emptyFetchIsRefusedOnceThenTrusted.
        settlements.stored = [Settlement(id: UUID(), groupID: group.id, fromUserID: carol,
                                         toUserID: alice, amount: 1, currency: "USD",
                                         recordedBy: carol,
                                         createdAt: Date().addingTimeInterval(-3600))]

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: expenses, settlementService: settlements,
                                currentUserIDProvider: { bob })
        await vm.load(showError: false)
        await vm.recordPayment(from: bob, to: alice, amount: 10)
        #expect(vm.balance(for: bob) == 0)
        let payment = try! #require(vm.settlements.first { $0.fromUserID == bob })

        settlements.deleteErrorAfterCommit = AppError.serverError("The request timed out.")
        await vm.deletePayment(payment)

        // The client could not tell the delete had landed, so it rolls back and reports — that
        // part is correct and unchanged. The server, meanwhile, no longer has the row.
        #expect(vm.settlements.contains { $0.id == payment.id })
        #expect(vm.errorAlert != nil)
        #expect(!settlements.stored.contains { $0.id == payment.id })

        vm.errorAlert = nil
        await vm.load(showError: false)

        // One ordinary refresh reconciles it: the phantom credit is gone and the full debt is
        // visible again. Nothing else can do this — a retry of the delete would fail the same
        // way, so the fetch has to be what clears it.
        #expect(!vm.settlements.contains { $0.id == payment.id })
        #expect(vm.settlements.count == 1)
        #expect(vm.balance(for: bob) == -10)
    }

    @Test("An empty settlements reload is refused once, then believed")
    func emptyFetchIsRefusedOnceThenTrusted() async {
        // `applyFetchedExpenses` guards against an empty reload for a non-empty group because
        // one was actually observed on this PostgREST surface; settlements had no such guard,
        // so a stale empty read silently showed gross, pre-payment debt. The guard here is
        // bounded on purpose: refusing every empty response forever would pin a ledger that
        // really was emptied elsewhere — the same permanent-credit defect from the other end.
        let group = makeGroup(); let alice = UUID(); let bob = UUID()
        let expenses = FakeExpenseService(); let settlements = FakeSettlementService()
        let e = Expense(id: UUID(), groupID: group.id, title: "Dinner", amount: 30,
                        currency: "USD", payerID: alice, category: .food, notes: nil,
                        receiptURL: nil, originalAmount: nil, originalCurrency: nil,
                        recurrence: .none, nextOccurrenceDate: nil, createdAt: Date())
        expenses.expenses = [e]
        expenses.splits = [Split(id: UUID(), expenseID: e.id, userID: bob, amount: 10,
                                 isSettled: false, settledAt: nil)]
        let recorded = Settlement(id: UUID(), groupID: group.id, fromUserID: bob,
                                  toUserID: alice, amount: 10, currency: "USD",
                                  recordedBy: alice, createdAt: Date())
        settlements.stored = [recorded]

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: expenses, settlementService: settlements,
                                currentUserIDProvider: { bob })
        await vm.load(showError: false)
        #expect(vm.balance(for: bob) == 0)

        settlements.stored = []
        await vm.load(showError: false)

        // First empty response: treated as a stale read. The payment stays and the user gets
        // the existing stale-balance warning rather than a silently inflated debt.
        #expect(vm.settlements.count == 1)
        #expect(vm.balance(for: bob) == 0)
        #expect(vm.balanceLoadFailed)

        await vm.load(showError: false)

        // Second, independent empty response: believed.
        #expect(vm.settlements.isEmpty)
        #expect(vm.balance(for: bob) == -10)
        #expect(!vm.balanceLoadFailed)
    }

    @Test("A pending payment sorts ahead of the fetched, newest-first ledger")
    func pendingPaymentSortsBeforeFetchedSettlements() async {
        // The fetch is `order(created_at, ascending: false)` and `recordPayment` inserts at
        // index 0, but the merge used to append pending rows — by definition the newest — at
        // the end, so a just-recorded payment jumped from the top of the list to the bottom on
        // the next load. Balances do not care; the payment history list in Tasks 6-8 does.
        let group = makeGroup(); let alice = UUID(); let bob = UUID()
        let expenses = FakeExpenseService(); let settlements = FakeSettlementService()
        let older = Settlement(id: UUID(), groupID: group.id, fromUserID: bob, toUserID: alice,
                               amount: 3, currency: "USD", recordedBy: bob,
                               createdAt: Date().addingTimeInterval(-3600))
        settlements.stored = [older]

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: expenses, settlementService: settlements,
                                currentUserIDProvider: { bob })
        await vm.load(showError: false)
        settlements.events = []

        // A fetch that snapshots `stored` before the payment below is recorded, so the payment
        // is still pending when the merge runs — the only state in which ordering is decided
        // by the merge rather than by `recordPayment`'s insert-at-zero.
        settlements.fetchDelay = .milliseconds(60)
        let loadTask = Task { await vm.load(showError: false) }
        try? await Task.sleep(for: .milliseconds(15))
        await vm.recordPayment(from: bob, to: alice, amount: 7)
        await loadTask.value

        #expect(settlements.events == ["fetch.start", "record", "fetch.end"])
        #expect(vm.settlements.count == 2)
        #expect(vm.settlements.first?.amount == 7)
        #expect(vm.settlements.last?.id == older.id)
    }
}

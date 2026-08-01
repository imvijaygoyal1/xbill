import Foundation
import Testing
@testable import xBill

/// Suspends a fake's async call at a chosen point until the test lets it go.
///
/// Replaces the sleep-based interleaving the settlement tests used through round 4
/// (`fetchDelay` / `deleteDelay`). Sleeps only made an interleaving *probable*: the window was
/// a fixed 60-220ms and the trigger a shorter sleep, so a scheduling hiccup under full-suite
/// load could reorder the two operations —
/// `pendingPaymentSortsBeforeFetchedSettlements` was observed failing that way once in a
/// full-suite run while passing in isolation. A gate makes the interleaving certain and removes
/// wall-clock time from these tests entirely.
///
/// Two rules keep the gate from trading a flaky test for a hung one, which is exactly what the
/// first draft of this helper did to the whole run:
///
/// 1. **Arming is one-shot.** `arm()` licenses exactly one park; `waitIfArmed` consumes it.
///    A gate left armed after the interleaving it was for cannot silently swallow an unrelated
///    later call. That is the defect this replaces: `deleteSurvivesConcurrentLoadCarryingTheRow`
///    armed the fetch gate, released it, and then made a further verification `load()` — which
///    parked on the still-armed gate with no `release()` left to come, stalling that test and
///    every test queued behind it in this `.serialized` suite.
/// 2. **Every wait is bounded.** A park or a wait that outlives `timeout` records an issue and
///    resumes. A mis-sequenced test then fails with a message naming the gate, instead of
///    taking the suite down with it.
@MainActor
final class InterleavingGate {
    /// Orders of magnitude longer than the microseconds a correct interleaving needs. A
    /// correctly sequenced test is not expected to reach it, but nothing here can rule that
    /// out — an expiry is a signal to check the sequencing first, not proof of a defect.
    static let timeout: Duration = .seconds(5)

    private var isArmed = false
    private var parked: CheckedContinuation<Void, Never>?
    private var waiters: [(token: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var parkToken = 0
    private var waiterToken = 0

    /// Licenses exactly one park. Call it again for each further call to be parked.
    func arm() { isArmed = true }

    /// Called from inside the fake. Suspends there until `release()`.
    func waitIfArmed() async {
        guard isArmed else { return }
        // `parked` holds one continuation. Parking a second call overwrites the first, which is
        // then never resumed — the task hangs forever, and the watchdog cannot report it because
        // its `parkToken == token` guard now fails for the stranded park. That is a silent hang
        // of the whole suite, which this file has already caused once. Refuse loudly instead.
        guard parked == nil else {
            Issue.record("InterleavingGate: armed while a park was still live. The gate holds one continuation; the earlier park would be stranded. Release it first.")
            return
        }
        isArmed = false
        parkToken += 1
        let token = parkToken
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            parked = continuation
            let pending = waiters
            waiters = []
            for waiter in pending { waiter.continuation.resume() }
            Task { @MainActor in
                try? await Task.sleep(for: Self.timeout)
                // Still the same park, still unreleased: the test is never going to release it.
                guard parkToken == token, parked != nil else { return }
                Issue.record("InterleavingGate: a parked call was not released within \(Self.timeout).")
                release()
            }
        }
    }

    /// Called from the test. Returns once the fake has actually reached the gate — so the test
    /// never races the operation it is trying to interleave with.
    func waitUntilParked() async {
        if parked != nil { return }
        waiterToken += 1
        let token = waiterToken
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append((token, continuation))
            Task { @MainActor in
                try? await Task.sleep(for: Self.timeout)
                guard let index = waiters.firstIndex(where: { $0.token == token }) else { return }
                Issue.record("InterleavingGate: no call reached the gate within \(Self.timeout). Was it armed?")
                waiters.remove(at: index).continuation.resume()
            }
        }
    }

    /// Called from the test. Lets the parked call run on.
    func release() {
        let continuation = parked
        parked = nil
        continuation?.resume()
    }
}

@MainActor
final class FakeSettlementService: SettlementDataProviding {
    var stored: [Settlement] = []
    var insertError: Error?
    var deleteError: Error?
    /// When set, `fetchSettlements` throws. Models the settlements-only outage behind C1: the
    /// members and expenses fetches succeed, and only the ledger read fails.
    var fetchError: Error?
    /// When set, `deleteSettlement` removes the row from `stored` and *then* throws — the
    /// commit-but-error case: a request that landed on the server while the client saw a
    /// timeout, a dropped response, or a 500 raised after the write. Distinct from
    /// `deleteError`, which throws before touching `stored`.
    var deleteErrorAfterCommit: Error?
    var deletedIDs: [UUID] = []
    /// Parks `fetchSettlements` *after* it has captured its snapshot — modelling a server read
    /// that started before a concurrent write committed, the IMP-1 race. `arm()` once per fetch
    /// to be parked; an unarmed fetch runs straight through.
    let fetchGate = InterleavingGate()
    /// Parks `deleteSettlement` before it touches `stored`, so a test can act while the delete
    /// is genuinely in flight. `arm()` once per delete to be parked.
    let deleteGate = InterleavingGate()
    /// Ordered log of call boundaries. A test that only asserts final state cannot tell a
    /// genuine interleaving from two operations that happened to run back-to-back — this is
    /// what lets a test assert the interleaving actually occurred.
    var events: [String] = []

    func fetchSettlements(groupID: UUID) async throws -> [Settlement] {
        events.append("fetch.start")
        let snapshot = stored
        await fetchGate.waitIfArmed()
        if let fetchError {
            events.append("fetch.failed")
            throw fetchError
        }
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
        await deleteGate.waitIfArmed()
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

        // Park a settlements fetch that has snapshotted `stored` (still empty) and can only
        // return after the payment below is recorded — a read that started first and resolved
        // second.
        settlements.fetchGate.arm()
        let loadTask = Task { await vm.load(showError: false) }
        await settlements.fetchGate.waitUntilParked()

        await vm.recordPayment(from: bob, to: alice, amount: 10)
        #expect(vm.balance(for: bob) == 0)

        settlements.fetchGate.release()
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
        settlements.deleteGate.arm()
        let deleteTask = Task { await vm.deletePayment(p1) }
        await settlements.deleteGate.waitUntilParked()

        // A different amount so this does not collide with the IMP-4 duplicate window.
        await vm.recordPayment(from: bob, to: alice, amount: 2)

        settlements.deleteGate.release()
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

    @Test("A successful delete is not undone by a load whose response still has the row")
    func deleteSurvivesConcurrentLoadCarryingTheRow() async {
        // The `.deleted` overlay branch of applyFetchedSettlements. A fetch that started before
        // the delete returns a snapshot that still contains the row; without the tombstone the
        // merge would put a deleted payment straight back and keep crediting the balance.
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
        let payment = try! #require(vm.settlements.first)
        #expect(vm.balance(for: bob) == 0)
        settlements.events = []

        // Snapshot taken now — it contains the payment — and released after the delete lands.
        settlements.fetchGate.arm()
        let loadTask = Task { await vm.load(showError: false) }
        await settlements.fetchGate.waitUntilParked()
        await vm.deletePayment(payment)
        settlements.fetchGate.release()
        await loadTask.value

        // Prove the delete really did land inside the fetch's window.
        #expect(settlements.events == ["fetch.start", "delete.start", "delete.end", "fetch.end"])
        #expect(vm.settlements.isEmpty)
        #expect(vm.balance(for: bob) == -10)

        // And it stays deleted once a fetch that started after the delete comes back. The gate
        // is one-shot, so this one is not parked.
        await vm.load(showError: false)
        #expect(vm.settlements.isEmpty)
        #expect(vm.balance(for: bob) == -10)
    }

    @Test("A load issued while the delete request is in flight cannot resurrect the row")
    func deleteSurvivesLoadIssuedDuringTheDeleteRequest() async {
        // Round-5 M1. The tombstone is tagged before the request, so it does not yet satisfy the
        // generation invariant — the row is still on the server when it is written. A `load()`
        // starting between the tag and the commit claims a higher generation, expires the
        // tombstone, and its response still contains the row. Reachable through the `isLoading`
        // hole: load A is in flight, deletePayment starts, A finishes and its `defer` clears the
        // flag for everyone, and load B is free to start while the delete is still awaiting.
        let group = makeGroup(); let alice = UUID(); let bob = UUID(); let carol = UUID()
        let expenses = FakeExpenseService(); let settlements = FakeSettlementService()
        let e = Expense(id: UUID(), groupID: group.id, title: "Dinner", amount: 30,
                        currency: "USD", payerID: alice, category: .food, notes: nil,
                        receiptURL: nil, originalAmount: nil, originalCurrency: nil,
                        recurrence: .none, nextOccurrenceDate: nil, createdAt: Date())
        expenses.expenses = [e]
        expenses.splits = [Split(id: UUID(), expenseID: e.id, userID: bob, amount: 10,
                                 isSettled: false, settledAt: nil)]
        // Unrelated payment between two other members, so no fetch here is ever empty and the
        // empty-response guard plays no part in what this test measures.
        settlements.stored = [Settlement(id: UUID(), groupID: group.id, fromUserID: carol,
                                         toUserID: alice, amount: 1, currency: "USD",
                                         recordedBy: carol,
                                         createdAt: Date().addingTimeInterval(-3600))]

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: expenses, settlementService: settlements,
                                currentUserIDProvider: { bob })
        await vm.load(showError: false)
        await vm.recordPayment(from: bob, to: alice, amount: 10)
        let payment = try! #require(vm.settlements.first { $0.fromUserID == bob })
        #expect(vm.balance(for: bob) == 0)
        settlements.events = []

        settlements.fetchGate.arm()
        settlements.deleteGate.arm()

        // Load A starts and parks holding a snapshot that still contains the payment.
        let loadA = Task { await vm.load(showError: false) }
        await settlements.fetchGate.waitUntilParked()

        // The delete starts — tagging its tombstone, removing the row locally — and parks
        // before the write reaches the server.
        let deleteTask = Task { await vm.deletePayment(payment) }
        await settlements.deleteGate.waitUntilParked()

        // Load A finishes. Its `defer { isLoading = false }` clears the flag the still-running
        // delete also set: the hole that lets load B start at all.
        settlements.fetchGate.release()
        await loadA.value
        #expect(!vm.isLoading)

        // Load B is issued while the delete is still in flight, so it claims a generation
        // higher than the tombstone and its response still contains the row.
        settlements.fetchGate.arm()
        let loadB = Task { await vm.load(showError: false) }
        await settlements.fetchGate.waitUntilParked()
        settlements.fetchGate.release()
        await loadB.value

        // Only now does the delete commit.
        settlements.deleteGate.release()
        await deleteTask.value

        // Both loads ran entirely inside the delete's request window — the interleaving this
        // test depends on, not a scheduling accident that serialised them.
        #expect(settlements.events == ["fetch.start", "delete.start", "fetch.end",
                                       "fetch.start", "fetch.end", "delete.end"])
        // The deleted payment must be gone and the full debt visible; the unrelated payment
        // must be untouched.
        #expect(!vm.settlements.contains { $0.id == payment.id })
        #expect(vm.settlements.count == 1)
        #expect(vm.balance(for: bob) == -10)

        // The gate is one-shot, so this final confirming fetch runs straight through.
        await vm.load(showError: false)
        #expect(!vm.settlements.contains { $0.id == payment.id })
        #expect(vm.balance(for: bob) == -10)
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
        settlements.fetchGate.arm()
        let loadTask = Task { await vm.load(showError: false) }
        await settlements.fetchGate.waitUntilParked()
        await vm.recordPayment(from: bob, to: alice, amount: 7)
        settlements.fetchGate.release()
        await loadTask.value

        #expect(settlements.events == ["fetch.start", "record", "fetch.end"])
        #expect(vm.settlements.count == 2)
        #expect(vm.settlements.first?.amount == 7)
        #expect(vm.settlements.last?.id == older.id)
    }

    @Test("A settlements-only fetch failure raises the stale-data warning")
    func settlementsFetchFailureRaisesBalanceLoadFailed() async {
        // C1. `load()` fetches members, expenses and settlements through one `try await` tuple,
        // so a settlements-only outage throws the whole `do`. The catch restores members and
        // expenses from cache and recomputes — against an empty `settlements` array. Every split
        // then counts as unpaid, which is the largest possible wrong number, and Settle Up puts
        // a Record Payment button on each row. `balanceLoadFailed` was cleared before the fetch
        // and never restored, so that figure was presented as authoritative with no warning:
        // a user could pay a debt they had already paid.
        let group = makeGroup(); let alice = UUID(); let bob = UUID()
        let e = Expense(id: UUID(), groupID: group.id, title: "Dinner", amount: 30,
                        currency: "USD", payerID: alice, category: .food, notes: nil,
                        receiptURL: nil, originalAmount: nil, originalCurrency: nil,
                        recurrence: .none, nextOccurrenceDate: nil, createdAt: Date())
        let split = Split(id: UUID(), expenseID: e.id, userID: bob, amount: 10,
                          isSettled: false, settledAt: nil)
        let repayment = Settlement(id: UUID(), groupID: group.id, fromUserID: bob,
                                   toUserID: alice, amount: 10, currency: "USD",
                                   recordedBy: bob, createdAt: Date())

        // A healthy load first. It also populates the expense cache, which is what the failing
        // VM below reads back — the real shape of this bug is a relaunch (or any later load)
        // where expenses are available and the ledger read is not.
        let healthyExpenses = FakeExpenseService()
        healthyExpenses.expenses = [e]; healthyExpenses.splits = [split]
        let healthySettlements = FakeSettlementService()
        healthySettlements.stored = [repayment]
        let healthyVM = GroupViewModel(group: group, groupService: FakeGroupService(),
                                       expenseService: healthyExpenses,
                                       settlementService: healthySettlements,
                                       currentUserIDProvider: { bob })
        await healthyVM.load(showError: false)
        #expect(healthyVM.balance(for: bob) == 0)
        #expect(!healthyVM.balanceLoadFailed)

        // Now the same group with only the settlements read failing.
        let expenses = FakeExpenseService()
        expenses.expenses = [e]; expenses.splits = [split]
        let settlements = FakeSettlementService()
        settlements.stored = [repayment]
        settlements.fetchError = AppError.networkUnavailable
        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: expenses, settlementService: settlements,
                                currentUserIDProvider: { bob })
        await vm.load(showError: false)

        // The number on screen really is the gross, pre-payment debt — the repayment exists on
        // the server and is nowhere in this VM. That is precisely why the warning must be up.
        #expect(vm.settlements.isEmpty)
        #expect(vm.balance(for: bob) == -10)
        #expect(vm.balanceLoadFailed)
    }

    @Test("A stale settlements response cannot overwrite a newer one")
    func staleSettlementsResponseIsDiscarded() async {
        // I4. Two `load()`s can be in flight at once: `deletePayment` takes no `!isLoading`
        // guard and its `defer` clears the flag while an earlier load is still awaiting, so the
        // next refresh sails past `load()`'s own guard. If the later load returns first, the
        // earlier one's older snapshot used to be applied wholesale on top of it — a payment
        // recorded in between disappeared and the balance reverted to gross.
        let group = makeGroup(); let alice = UUID(); let bob = UUID()
        let expenses = FakeExpenseService(); let settlements = FakeSettlementService()
        let e = Expense(id: UUID(), groupID: group.id, title: "Dinner", amount: 30,
                        currency: "USD", payerID: alice, category: .food, notes: nil,
                        receiptURL: nil, originalAmount: nil, originalCurrency: nil,
                        recurrence: .none, nextOccurrenceDate: nil, createdAt: Date())
        expenses.expenses = [e]
        expenses.splits = [Split(id: UUID(), expenseID: e.id, userID: bob, amount: 10,
                                 isSettled: false, settledAt: nil)]
        // A small earlier payment by bob, so he can delete it — the isLoading hole this needs.
        let earlier = Settlement(id: UUID(), groupID: group.id, fromUserID: bob, toUserID: alice,
                                 amount: 2, currency: "USD", recordedBy: bob,
                                 createdAt: Date().addingTimeInterval(-3600))
        settlements.stored = [earlier]

        let vm = GroupViewModel(group: group, groupService: FakeGroupService(),
                                expenseService: expenses, settlementService: settlements,
                                currentUserIDProvider: { bob })
        await vm.load(showError: false)
        #expect(vm.balance(for: bob) == -8)
        settlements.events = []

        // Load A starts and parks holding a snapshot that still contains only `earlier`.
        settlements.fetchGate.arm()
        let loadA = Task { await vm.load(showError: false) }
        await settlements.fetchGate.waitUntilParked()

        // Deleting `earlier` completes while load A is still parked; its `defer` clears
        // `isLoading` for everyone, which is what lets load B start below.
        await vm.deletePayment(earlier)
        #expect(!vm.isLoading)

        // A full repayment is recorded in the same window.
        await vm.recordPayment(from: bob, to: alice, amount: 10)
        #expect(vm.balance(for: bob) == 0)

        // Load B is issued and returns the true current ledger. The gate is one-shot and load A
        // consumed it, so B runs straight through.
        await vm.load(showError: false)
        #expect(vm.balance(for: bob) == 0)

        // Only now does load A come back, carrying a snapshot that predates both the delete and
        // the payment.
        settlements.fetchGate.release()
        await loadA.value

        // Both later fetches really did complete inside load A's window.
        #expect(settlements.events == ["fetch.start", "delete.start", "delete.end", "record",
                                       "fetch.start", "fetch.end", "fetch.end"])
        // Load A's response is older than the one already applied, so it is discarded whole:
        // the repayment survives, the deleted payment stays deleted, the balance holds.
        #expect(vm.settlements.count == 1)
        #expect(vm.settlements.first?.amount == 10)
        #expect(vm.balance(for: bob) == 0)
    }
}

// MARK: - Atomic state change (device crash 2026-08-01)

@Suite("Payment paths recompute without suspending")
@MainActor
struct PaymentRecomputeIsSynchronousTests {

    private func makeGroup() -> BillGroup {
        BillGroup(id: UUID(), name: "Trip", emoji: "✈️", createdBy: UUID(),
                  isArchived: false, currency: "USD", createdAt: Date())
    }

    /// `deletePayment` removed the row from `settlements`, then `await computeBalances()` —
    /// which fetched splits over the network before reassigning `settlementSuggestions`. That
    /// `await` split one user action into two separately published mutations of the same
    /// `List`, landing either side of a network round-trip while the swipe-delete animation
    /// was still running. `UICollectionView` aborted with `NSInternalInconsistencyException`:
    /// "the number of items ... after the update (3) must be equal to the number ... before
    /// the update (2), plus or minus the number inserted (0)".
    ///
    /// Recording or deleting a payment cannot change a split, so the fetch was never needed.
    /// Asserting zero fetches is how "both mutations happen in one synchronous turn" is
    /// pinned: a fetch is the suspension point, and no fetch means no suspension.
    @Test("Recording and deleting a payment fetch no splits")
    func paymentPathsDoNotRefetchSplits() async {
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

        // Baseline: load() legitimately fetches splits. Everything after it must not.
        let afterLoad = expenses.fetchSplitsCount
        #expect(afterLoad > 0, "load() is still expected to fetch splits")

        await vm.recordPayment(from: bob, to: alice, amount: 10)
        #expect(expenses.fetchSplitsCount == afterLoad, "recordPayment must not refetch splits")
        #expect(vm.balance(for: bob) == 0, "the balance must still be recomputed")

        let payment = try! #require(vm.settlements.first)
        await vm.deletePayment(payment)
        #expect(expenses.fetchSplitsCount == afterLoad, "deletePayment must not refetch splits")
        #expect(vm.balance(for: bob) == -10, "the debt must come back")
        #expect(vm.settlementSuggestions.count == 1, "the suggestion must be restored in the same turn")
    }
}

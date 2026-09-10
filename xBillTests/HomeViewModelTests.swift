//
//  HomeViewModelTests.swift
//  xBillTests
//
//  HOME-01. `HomeViewModel` had **no `init`**: `GroupService.shared`, `ExpenseService.shared` and
//  `AuthService.shared` were stored properties, `SettlementService` and `NetworkMonitor` were
//  reached through `.shared` inline, and nothing in the test target could construct the type. The
//  screen every user lands on — and the only place cross-group balances are summed — had zero
//  unit coverage. These are its first tests.
//
//  Every view model here injects all five seams. See `GroupViewModelSettlementTests.swift` for
//  what omitting `isConnectedProvider` cost when it was left to the real `NWPathMonitor`.
//

import Foundation
import Testing
@testable import xBill

// MARK: - Fakes

@MainActor
final class FakeHomeGroupService: HomeGroupDataProviding {
    var groups: [BillGroup] = []
    var archivedGroups: [BillGroup] = []
    var members: [UUID: [User]] = [:]
    var fetchGroupsError: Error?

    private(set) var fetchGroupsCount = 0
    private(set) var fetchArchivedCount = 0
    private(set) var deletedGroupIDs: [UUID] = []

    /// Parks `fetchArchivedGroups` so a test can observe what else is in flight while it waits.
    let archivedGate = InterleavingGate()

    func fetchGroups(for userID: UUID) async throws -> [BillGroup] {
        fetchGroupsCount += 1
        if let fetchGroupsError { throw fetchGroupsError }
        return groups
    }

    func fetchArchivedGroups(for userID: UUID) async throws -> [BillGroup] {
        fetchArchivedCount += 1
        await archivedGate.waitIfArmed()
        return archivedGroups
    }

    func fetchMembers(groupID: UUID, includeInactive: Bool) async throws -> [User] {
        members[groupID] ?? []
    }

    func addMember(groupId: UUID, userId: UUID) async throws {}
    func removeMember(groupId: UUID, userId: UUID) async throws {}
    func updateGroup(_ group: BillGroup) async throws -> BillGroup { group }

    func createGroup(name: String, emoji: String, currency: String, createdBy: UUID) async throws -> BillGroup {
        BillGroup(id: UUID(), name: name, emoji: emoji, createdBy: createdBy,
                  isArchived: false, currency: currency, createdAt: Date())
    }

    func deleteGroup(groupId: UUID) async throws { deletedGroupIDs.append(groupId) }

    func groupChanges(userID: UUID, groupIDs: [UUID]) async throws -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}

@MainActor
final class FakeHomeExpenseService: HomeExpenseDataProviding {
    var expenses: [UUID: [Expense]] = [:]
    var splits: [Split] = []

    private(set) var fetchExpensesCount = 0

    /// Parks `fetchExpenses`, which puts a `computeBalances` run in flight — after it has read
    /// `groups` and built its task group, but before it has any result to publish.
    let fetchGate = InterleavingGate()

    func fetchExpenses(groupID: UUID, limit: Int?) async throws -> [Expense] {
        fetchExpensesCount += 1
        await fetchGate.waitIfArmed()
        return expenses[groupID] ?? []
    }

    func fetchSplits(expenseIDs: [UUID]) async throws -> [Split] {
        splits.filter { expenseIDs.contains($0.expenseID) }
    }

    func deleteExpense(id: UUID) async throws {}
    func fetchDueRecurringExpenses(groupID: UUID) async throws -> [Expense] { [] }
    func createRecurringInstance(templateID: UUID, expectedNextOccurrence: Date,
                                 newNextOccurrence: Date) async throws -> Expense? { nil }
    func notifySettlementRecorded(settlementID: UUID) async {}

    func createExpense(
        groupID: UUID, title: String, amount: Decimal, currency: String,
        payerID: UUID, category: Expense.Category, notes: String?, splits: [SplitInput],
        originalAmount: Decimal?, originalCurrency: String?,
        recurrence: Expense.Recurrence, nextOccurrenceDate: Date?
    ) async throws -> Expense {
        Expense(id: UUID(), groupID: groupID, title: title, amount: amount, currency: currency,
                payerID: payerID, category: category, notes: notes, receiptURL: nil,
                originalAmount: originalAmount, originalCurrency: originalCurrency,
                recurrence: recurrence, nextOccurrenceDate: nextOccurrenceDate, createdAt: Date())
    }
}

// MARK: - Fixture

@MainActor
private struct HomeFixture {
    let alice = UUID()
    let bob = UUID()
    let group: BillGroup
    let expense: Expense
    let groups = FakeHomeGroupService()
    let expenses = FakeHomeExpenseService()
    let settlements = FakeSettlementService()

    /// Alice paid 30; Bob owes 10 of it. Seen as Bob, the net is **-10**.
    init() {
        let groupID = UUID()
        group = BillGroup(id: groupID, name: "Trip", emoji: "✈️", createdBy: alice,
                          isArchived: false, currency: "USD", createdAt: Date())
        expense = Expense(id: UUID(), groupID: groupID, title: "Dinner", amount: 30,
                          currency: "USD", payerID: alice, category: .food, notes: nil,
                          receiptURL: nil, originalAmount: nil, originalCurrency: nil,
                          recurrence: .none, nextOccurrenceDate: nil, createdAt: Date())
        groups.groups = [group]
        groups.members[groupID] = [
            User(id: alice, email: "alice@example.com", displayName: "Alice",
                 avatarURL: nil, isActive: true, createdAt: Date()),
            User(id: bob, email: "bob@example.com", displayName: "Bob",
                 avatarURL: nil, isActive: true, createdAt: Date())
        ]
        expenses.expenses[groupID] = [expense]
        expenses.splits = [Split(id: UUID(), expenseID: expense.id, userID: bob, amount: 10)]
    }

    var currentUser: User {
        User(id: bob, email: "bob@example.com", displayName: "Bob",
             avatarURL: nil, isActive: true, createdAt: Date())
    }

    func makeViewModel(connected: Bool = true) -> HomeViewModel {
        let user = currentUser
        return HomeViewModel(groupService: groups,
                             expenseService: expenses,
                             settlementService: settlements,
                             currentUserProvider: { user },
                             isConnectedProvider: { connected })
    }
}

// MARK: - loadAll

@Suite("HomeViewModel — loadAll", .serialized)
@MainActor
struct HomeViewModelLoadTests {

    @Test("Without a current user, loadAll does nothing at all")
    func noCurrentUserIsANoOp() async {
        let fixture = HomeFixture()
        let vm = fixture.makeViewModel()
        // `loadCurrentUser()` deliberately not called.
        await vm.loadAll()

        #expect(fixture.groups.fetchGroupsCount == 0)
        #expect(vm.groups.isEmpty)
        #expect(vm.errorAlert == nil, "there is nothing to report — the user simply is not loaded yet")
    }

    @Test("Online, loadAll sums the balance across the user's groups")
    func onlineComputesBalances() async {
        let fixture = HomeFixture()
        let vm = fixture.makeViewModel()
        await vm.loadCurrentUser()
        await vm.loadAll()

        #expect(vm.groups.map(\.id) == [fixture.group.id])
        #expect(vm.totalOwing == 10, "Bob owes Alice 10")
        #expect(vm.totalOwed == .zero)
        #expect(vm.netBalance == -10)
        #expect(vm.groupNetBalances[fixture.group.id] == -10)
        #expect(vm.groupMemberCounts[fixture.group.id] == 2)
        #expect(vm.recentExpenses.map(\.expense.id) == [fixture.expense.id])
        #expect(vm.errorAlert == nil)
    }

    /// A recorded payment cancels the debt. This is the arithmetic IMP-2 protects: if the
    /// settlements read fails the split still counts as unpaid, which is the largest possible
    /// wrong number rather than a small one.
    @Test("A settlement offsets the debt it repays")
    func settlementOffsetsTheDebt() async {
        let fixture = HomeFixture()
        fixture.settlements.stored = [
            Settlement(id: UUID(), groupID: fixture.group.id, fromUserID: fixture.bob,
                       toUserID: fixture.alice, amount: 10, currency: "USD",
                       recordedBy: fixture.bob, createdAt: Date())
        ]
        let vm = fixture.makeViewModel()
        await vm.loadCurrentUser()
        await vm.loadAll()

        #expect(vm.netBalance == .zero)
        #expect(vm.groupNetBalances[fixture.group.id] == .zero)
    }

    @Test("A failed settlements fetch warns that balances may be stale")
    func settlementsFailureRaisesTheStaleWarning() async {
        let fixture = HomeFixture()
        fixture.settlements.fetchError = AppError.serverError("ledger unavailable")
        let vm = fixture.makeViewModel()
        await vm.loadCurrentUser()
        await vm.loadAll()

        // The gross, pre-payment debt is what gets shown — so it must not be shown silently.
        #expect(vm.netBalance == -10)
        #expect(vm.errorAlert?.title == "Some balances may be stale")
    }

    /// The mirror of FLAKE-02, from the other side: offline must read the cache and must not
    /// reach the service. `CacheService.shared` is a process-wide singleton, so this test asserts
    /// what was *not* called rather than seeding it — seeding would reintroduce exactly the kind
    /// of shared-state coupling FLAKE-02 and FLAKE-03 removed.
    @Test("Offline, loadAll never touches the network")
    func offlineDoesNotReachTheService() async {
        let fixture = HomeFixture()
        let vm = fixture.makeViewModel(connected: false)
        await vm.loadCurrentUser()
        await vm.loadAll()

        #expect(fixture.groups.fetchGroupsCount == 0)
        #expect(fixture.expenses.fetchExpensesCount == 0)
        #expect(vm.totalOwed == .zero)
        #expect(vm.totalOwing == .zero)
    }
}

// MARK: - The concurrency the load order depends on

@Suite("HomeViewModel — load ordering", .serialized)
@MainActor
struct HomeViewModelOrderingTests {

    /// Pins the 2026-09-10 change. `loadAll` used to `await loadArchivedGroups()` before
    /// `computeBalances(for:)`, putting a whole round trip for data **Home does not render** ahead
    /// of the numbers the user is waiting for. They run concurrently now.
    ///
    /// Asserting only that both finished would pass just as well if they were re-serialised. So
    /// this parks the archived fetch and checks that the balance fetches have *already started*
    /// while it is still in flight — the overlap itself, not its result.
    @Test("The balances do not wait for the archived-groups fetch")
    func balancesOverlapTheArchivedFetch() async {
        let fixture = HomeFixture()
        let vm = fixture.makeViewModel()
        await vm.loadCurrentUser()

        fixture.groups.archivedGate.arm()
        let load = Task { await vm.loadAll() }

        await fixture.groups.archivedGate.waitUntilParked()

        // Reaching the gate only means the archived task suspended; the balances task is enqueued
        // on the same actor and may not have been scheduled yet. Yield until it has, rather than
        // asserting into that gap — the first draft of this test failed for exactly that reason.
        // The bound still discriminates: were the two re-serialised, `computeBalances` could not
        // start at all while the archived fetch is parked, so no number of yields would satisfy it.
        var yields = 0
        while fixture.expenses.fetchExpensesCount == 0 && yields < 200 {
            await Task.yield()
            yields += 1
        }
        #expect(fixture.expenses.fetchExpensesCount > 0,
                "the balance fetches must be under way while the archived fetch is still parked")

        fixture.groups.archivedGate.release()
        await load.value

        #expect(vm.netBalance == -10, "and the load must still finish correctly")
    }

    /// A realtime event and a pull-to-refresh both call `loadAll`, and nothing serialises them.
    ///
    /// `computeBalances(for:)` guards on `isComputingBalances` and, before this was fixed, simply
    /// **returned** when a run was already in flight. That is only harmless while both callers see
    /// the same group list. The ordering below is the one that hurts, and it is the ordering a
    /// realtime event produces:
    ///
    ///   1. load #1 reads `groups`, starts computing, and is still fetching
    ///   2. a group appears; load #2 fetches the **new** list and assigns it
    ///   3. load #2's recompute is dropped, because #1 is still running
    ///   4. #1 finishes and publishes totals for the list it read in step 1
    ///
    /// Home then renders a total that omits a group it is simultaneously listing. Both `await`s
    /// returned, nothing threw, and the numbers are simply wrong — the same silent shape as
    /// FLAKE-02.
    @Test("A load that arrives while balances are in flight is not silently dropped")
    func overlappingLoadStillRecomputes() async {
        let fixture = HomeFixture()
        let vm = fixture.makeViewModel()
        await vm.loadCurrentUser()

        // 1. Park load #1 inside its balance computation.
        fixture.expenses.fetchGate.arm()
        let first = Task { await vm.loadAll() }
        await fixture.expenses.fetchGate.waitUntilParked()

        // 2. A second group appears — the case a realtime event exists to deliver.
        let second = BillGroup(id: UUID(), name: "Flat", emoji: "🏠", createdBy: fixture.alice,
                               isArchived: false, currency: "USD", createdAt: Date())
        let secondExpense = Expense(id: UUID(), groupID: second.id, title: "Rent", amount: 100,
                                    currency: "USD", payerID: fixture.alice, category: .other,
                                    notes: nil, receiptURL: nil, originalAmount: nil,
                                    originalCurrency: nil, recurrence: .none,
                                    nextOccurrenceDate: nil, createdAt: Date())
        fixture.groups.groups = [fixture.group, second]
        fixture.groups.members[second.id] = fixture.groups.members[fixture.group.id]
        fixture.expenses.expenses[second.id] = [secondExpense]
        fixture.expenses.splits.append(
            Split(id: UUID(), expenseID: secondExpense.id, userID: fixture.bob, amount: 25))

        // 3. Load #2 sees the new list. Its recompute is the one that must not be lost.
        await vm.loadAll()

        // 4. Let #1 finish, publishing totals derived from the list it read before step 2.
        fixture.expenses.fetchGate.release()
        await first.value

        #expect(vm.groups.count == 2, "the new group is listed…")
        #expect(vm.groupNetBalances[second.id] == -25, "…so its balance must be there too")
        #expect(vm.netBalance == -35)
    }
}

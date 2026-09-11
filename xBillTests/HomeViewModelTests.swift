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
    private(set) var fetchMembersCount = 0
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
        fetchMembersCount += 1
        return members[groupID] ?? []
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

    // MARK: PERF-02

    /// `nil` means the RPC is unavailable and the view model should fall back to the per-group
    /// path — which is what an undeployed migration looks like from the client.
    var balanceRows: [GroupBalanceRow]?
    var balanceRowsError: Error?
    private(set) var groupBalancesCount = 0

    func groupBalances() async throws -> [GroupBalanceRow] {
        groupBalancesCount += 1
        if let balanceRowsError { throw balanceRowsError }
        guard let balanceRows else { throw AppError.serverError("no rows configured") }
        return balanceRows
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

    /// Spotlight indexing and the widget reload are stubbed out. Both are XPC calls to system
    /// daemons; a unit suite has no business writing to the simulator's real Spotlight index, and
    /// their cost under a parallel run is not something the test controls.
    func makeViewModel(connected: Bool = true) -> HomeViewModel {
        let user = currentUser
        return HomeViewModel(groupService: groups,
                             expenseService: expenses,
                             settlementService: settlements,
                             currentUserProvider: { user },
                             isConnectedProvider: { connected },
                             indexGroupsForSearch: { _ in },
                             reloadWidgets: { })
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

    /// Three callers hit `loadAll` on every cold launch — `MainTabView.task`,
    /// `startRealtimeUpdates`'s bootstrap, and `didBecomeActive` — within about 300 ms of each
    /// other. Measured on device before this was fixed: three full round trips, with Home's
    /// numbers landing only when the last finished, 723–973 ms in.
    @Test("Overlapping loads share one fetch instead of repeating it")
    func overlappingLoadsAreDeduplicated() async {
        let fixture = HomeFixture()
        let vm = fixture.makeViewModel()
        await vm.loadCurrentUser()

        fixture.expenses.fetchGate.arm()
        let first = Task { await vm.loadAll() }
        await fixture.expenses.fetchGate.waitUntilParked()

        // The two redundant launch callers, arriving while the first load is still fetching.
        let second = Task { await vm.loadAll() }
        let third = Task { await vm.loadAll() }
        await Task.yield()

        fixture.expenses.fetchGate.release()
        await first.value
        await second.value
        await third.value

        #expect(fixture.groups.fetchGroupsCount == 1,
                "three callers, one fetch — this was 3 before the fix")
        #expect(vm.netBalance == -10, "and every caller still sees a loaded screen")
    }

    /// The joiners must not return early: a caller that gets nothing would end pull-to-refresh's
    /// spinner instantly, which is indistinguishable from a refresh that failed.
    @Test("A joined caller waits for the running load rather than returning empty")
    func joinedCallerWaitsForTheResult() async {
        let fixture = HomeFixture()
        let vm = fixture.makeViewModel()
        await vm.loadCurrentUser()

        fixture.expenses.fetchGate.arm()
        let first = Task { await vm.loadAll() }
        await fixture.expenses.fetchGate.waitUntilParked()

        var joinerFinished = false
        let joiner = Task {
            await vm.loadAll()
            joinerFinished = true
        }
        await Task.yield()
        #expect(joinerFinished == false, "it must still be waiting while the load is parked")

        fixture.expenses.fetchGate.release()
        await first.value
        await joiner.value
        #expect(joinerFinished)
        #expect(vm.netBalance == -10)
    }

    /// Within a single group, `fullBalancesInGroup` fetched expenses, then members, then splits,
    /// then settlements — **four round trips one after another, per group**. Only splits needs
    /// expenses; members and settlements need nothing. Two groups meant eight sequential-per-group
    /// requests, and it grows with every group joined.
    ///
    /// Asserting the four results would pass equally well if they were still sequential, so this
    /// parks the head of the chain and checks the independent two have *already started*.
    @Test("Members and settlements do not wait for the expenses fetch")
    func perGroupFetchesOverlap() async {
        let fixture = HomeFixture()
        let vm = fixture.makeViewModel()
        await vm.loadCurrentUser()

        fixture.expenses.fetchGate.arm()
        let load = Task { await vm.loadAll() }
        await fixture.expenses.fetchGate.waitUntilParked()

        // Bounded yield rather than an instant assert: reaching the gate only means the expenses
        // task suspended, not that its siblings have been scheduled. If they were still chained
        // behind it they could never start while it is parked, so the bound still discriminates.
        var yields = 0
        while (fixture.groups.fetchMembersCount == 0
               || !fixture.settlements.events.contains("fetch.start")) && yields < 200 {
            await Task.yield()
            yields += 1
        }

        #expect(fixture.groups.fetchMembersCount > 0,
                "the members fetch must not queue behind the expenses fetch")
        #expect(fixture.settlements.events.contains("fetch.start"),
                "nor must the settlements fetch")

        fixture.expenses.fetchGate.release()
        await load.value
        #expect(vm.netBalance == -10, "and the result must still be right")
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

        // 3. The realtime stream's load — `force`, because the event says the row changed now.
        //    It joins #1 rather than racing it, and requires one further pass afterwards. Started
        //    as a task, not awaited here: it cannot finish until #1 does, and #1 is parked.
        let second_load = Task { await vm.loadAll(force: true) }
        await Task.yield()

        // 4. Let #1 finish. Its totals derive from the list it read before step 2, so the forced
        //    pass is the only thing that can pick the new group up.
        fixture.expenses.fetchGate.release()
        await first.value
        await second_load.value

        #expect(vm.groups.count == 2, "the new group is listed…")
        #expect(vm.groupNetBalances[second.id] == -25, "…so its balance must be there too")
        #expect(vm.netBalance == -35)
    }
}

// MARK: - PERF-02 — one request instead of three per group

/// `get_group_balances()` replaces the per-group members, splits and settlements fetches. These
/// pin the two things that make it worth doing (one call regardless of group count, and the same
/// numbers as the path it replaces) and the one that makes it safe to ship (a failure falls back
/// rather than showing nothing).
@Suite("HomeViewModel — balances from the server", .serialized)
@MainActor
struct HomeViewModelServerBalanceTests {

    private static let alice = UUID()
    private static let bob   = UUID()

    private static func row(group: UUID, user: UUID, name: String,
                            active: Bool = true, balance: String) -> GroupBalanceRow {
        GroupBalanceRow(
            groupID: group, currency: "USD", userID: user,
            email: "\(name.lowercased())@example.com", displayName: name,
            avatarURL: nil, venmoHandle: nil, paypalHandle: nil,
            isActive: active, createdAt: Date(), balance: balance)
    }

    /// Two groups, so "one call" is distinguishable from "one call per group".
    private func twoGroupFixture() -> (HomeFixture, BillGroup) {
        let fixture = HomeFixture()
        let second = BillGroup(id: UUID(), name: "Flat", emoji: "🏠", createdBy: Self.alice,
                               isArchived: false, currency: "USD", createdAt: Date())
        fixture.groups.groups = [fixture.group, second]
        fixture.groups.balanceRows = [
            Self.row(group: fixture.group.id, user: fixture.bob,   name: "Bob",   balance: "-10.00"),
            Self.row(group: fixture.group.id, user: fixture.alice, name: "Alice", balance: "10.00"),
            Self.row(group: second.id,        user: fixture.bob,   name: "Bob",   balance: "-25.50"),
            Self.row(group: second.id,        user: fixture.alice, name: "Alice", balance: "25.50")
        ]
        return (fixture, second)
    }

    @Test("Two groups cost one balances request, not three fetches each")
    func oneRequestForEveryGroup() async {
        let (fixture, _) = twoGroupFixture()
        let vm = fixture.makeViewModel()
        await vm.loadCurrentUser()
        await vm.loadAll()

        #expect(fixture.groups.groupBalancesCount == 1, "one call, for both groups")
        #expect(fixture.groups.fetchMembersCount == 0, "members come from the same response")
        #expect(fixture.settlements.events.isEmpty, "so do settlements")
        // Expenses are still per-group: the Recent Expenses list needs the rows themselves.
        #expect(fixture.expenses.fetchExpensesCount == 2)
    }

    @Test("The totals match what the rows say")
    func totalsComeFromTheRows() async {
        let (fixture, second) = twoGroupFixture()
        let vm = fixture.makeViewModel()
        await vm.loadCurrentUser()
        await vm.loadAll()

        #expect(vm.groupNetBalances[fixture.group.id] == Decimal(string: "-10.00"))
        #expect(vm.groupNetBalances[second.id] == Decimal(string: "-25.50"))
        #expect(vm.totalOwing == Decimal(string: "35.50"))
        #expect(vm.totalOwed == .zero)
        #expect(vm.groupMemberCounts[fixture.group.id] == 2)
        #expect(vm.errorAlert == nil)
    }

    /// Fractional balances must accumulate exactly across groups.
    ///
    /// This is what `balance` crossing as a *string* buys. It asserts the outcome — an exact sum —
    /// rather than trying to demonstrate a particular float artefact: an earlier version of this
    /// test claimed `Decimal(10.10)` differs from `Decimal(string: "10.10")` and it does not, so
    /// that assertion could never have failed. Summed cents are the property worth pinning.
    @Test("Fractional balances accumulate exactly across groups")
    func fractionalBalancesAccumulateExactly() async {
        let (fixture, second) = twoGroupFixture()
        fixture.groups.balanceRows = [
            Self.row(group: fixture.group.id, user: fixture.bob,   name: "Bob",   balance: "-10.10"),
            Self.row(group: fixture.group.id, user: fixture.alice, name: "Alice", balance: "10.10"),
            Self.row(group: second.id,        user: fixture.bob,   name: "Bob",   balance: "-20.20"),
            Self.row(group: second.id,        user: fixture.alice, name: "Alice", balance: "20.20")
        ]
        let vm = fixture.makeViewModel()
        await vm.loadCurrentUser()
        await vm.loadAll()

        #expect(vm.totalOwing == Decimal(string: "30.30"), "cents must not drift in the sum")
        #expect(vm.netBalance == Decimal(string: "-30.30"))
    }

    /// Inactive members still appear — they can hold a balance — but must not be counted as
    /// members of the group.
    @Test("A removed member keeps their balance and leaves the member count")
    func inactiveMemberCounted() async {
        let fixture = HomeFixture()
        fixture.groups.balanceRows = [
            Self.row(group: fixture.group.id, user: fixture.bob, name: "Bob", balance: "-10.00"),
            Self.row(group: fixture.group.id, user: fixture.alice, name: "Alice",
                     active: false, balance: "10.00")
        ]
        let vm = fixture.makeViewModel()
        await vm.loadCurrentUser()
        await vm.loadAll()

        #expect(vm.groupMemberCounts[fixture.group.id] == 1, "only the active one is counted")
        #expect(vm.groupNetBalances[fixture.group.id] == Decimal(string: "-10.00"))
    }

    /// What an undeployed migration looks like from the client. It must not blank the screen.
    @Test("A failed balances call falls back to computing them locally")
    func failureFallsBackToTheLocalPath() async {
        let fixture = HomeFixture()
        fixture.groups.balanceRowsError = AppError.serverError("function does not exist")
        let vm = fixture.makeViewModel()
        await vm.loadCurrentUser()
        await vm.loadAll()

        #expect(fixture.groups.fetchMembersCount > 0, "the local path ran")
        #expect(vm.netBalance == -10, "and produced the same answer")
        #expect(vm.errorAlert == nil, "a fallback that worked is not an error")
    }

    /// A balance that will not parse must never be read as zero — that silently cancels a debt.
    @Test("An unparseable balance falls back rather than reading as zero")
    func unparseableBalanceFallsBack() async {
        let fixture = HomeFixture()
        fixture.groups.balanceRows = [
            Self.row(group: fixture.group.id, user: fixture.bob, name: "Bob", balance: "not a number")
        ]
        let vm = fixture.makeViewModel()
        await vm.loadCurrentUser()
        await vm.loadAll()

        #expect(fixture.groups.fetchMembersCount > 0, "it fell back")
        #expect(vm.netBalance == -10, "rather than reporting a settled group")
    }
}

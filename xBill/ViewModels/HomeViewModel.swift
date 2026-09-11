//
//  HomeViewModel.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Observation
import SwiftUI
import WidgetKit

@Observable
@MainActor
final class HomeViewModel {

    // MARK: - State

    var groups: [BillGroup] = []
    var archivedGroups: [BillGroup] = []
    var currentUser: User?
    var groupsNavigationPath = NavigationPath()
    var totalOwed: Decimal = .zero
    var totalOwing: Decimal = .zero
    var recentExpenses: [RecentEntry] = []
    var crossGroupSuggestions: [SettlementSuggestion] = []
    var groupMemberCounts: [UUID: Int] = [:]
    var groupNetBalances: [UUID: Decimal] = [:]
    var isLoading: Bool = false
    var errorAlert: ErrorAlert?
    @ObservationIgnored private var isComputingBalances = false
    @ObservationIgnored private var shouldRecomputeBalances = false
    @ObservationIgnored private var inFlightLoad: Task<Void, Never>?
    @ObservationIgnored private var shouldReloadAgain = false
    @ObservationIgnored private var realtimeTask: Task<Void, Never>?

    struct RecentEntry: Identifiable, Sendable {
        var id: UUID { expense.id }
        let expense: Expense
        let members: [User]
    }

    private struct GroupBalanceData: Sendable {
        let groupID:     UUID
        let owed:        Decimal
        let owing:       Decimal
        let netBalance:  Decimal
        let memberCount: Int
        let entries:     [RecentEntry]
        let currency:    String
        let balances:    [UUID: Decimal]
        let names:       [UUID: String]
        let loadFailed:   Bool
    }

    // HOME-01: these were `= GroupService.shared` / `= ExpenseService.shared` /
    // `= AuthService.shared`, with `SettlementService.shared` and `NetworkMonitor.shared` reached
    // inline further down. The type had no `init`, so nothing in the test target could construct
    // it and `loadAll` — the screen every user lands on — had no unit coverage at all. The seams
    // mirror `GroupViewModel`'s, including the argument order, so the two read the same way.
    private let groupService: any HomeGroupDataProviding
    private let expenseService: any HomeExpenseDataProviding
    private let settlementService: any SettlementDataProviding
    private let currentUserProvider: @MainActor () async throws -> User
    private let isConnectedProvider: @MainActor () -> Bool
    /// Two side effects that leave the process: `CSSearchableIndex.indexSearchableItems` and
    /// `WidgetCenter.reloadAllTimelines` are both XPC calls to system daemons. Seamed so the unit
    /// suite does not write to the simulator's real Spotlight index or poke the widget daemon on
    /// every `loadAll` — a genuine side effect from a unit test, and one whose cost is not under
    /// the test's control.
    private let indexGroupsForSearch: @MainActor ([BillGroup]) -> Void
    private let reloadWidgets: @MainActor () -> Void

    init(
        groupService: any HomeGroupDataProviding = GroupService.shared,
        expenseService: any HomeExpenseDataProviding = ExpenseService.shared,
        settlementService: any SettlementDataProviding = SettlementService.shared,
        currentUserProvider: @escaping @MainActor () async throws -> User = { try await AuthService.shared.currentUser() },
        isConnectedProvider: @escaping @MainActor () -> Bool = { NetworkMonitor.shared.isConnected },
        indexGroupsForSearch: @escaping @MainActor ([BillGroup]) -> Void = { SpotlightService.indexGroups($0) },
        reloadWidgets: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.groupService = groupService
        self.expenseService = expenseService
        self.settlementService = settlementService
        self.currentUserProvider = currentUserProvider
        self.isConnectedProvider = isConnectedProvider
        self.indexGroupsForSearch = indexGroupsForSearch
        self.reloadWidgets = reloadWidgets
    }

    // MARK: - Computed

    var netBalance: Decimal { totalOwed - totalOwing }

    // MARK: - Load

    func loadCurrentUser() async {
        do {
            currentUser = try await currentUserProvider()
        } catch {
            AppDiagnostics.log(.balance, "HomeViewModel.loadCurrentUser.catch", [
                ("silent", AppError.isSilent(error)),
                ("error", AppDiagnostics.describe(error))
            ])
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    /// Joins a load that is already running instead of starting a second one.
    ///
    /// Measured on device, three cold launches: **three** full `loadAll` round trips every time,
    /// ~10 ms and ~300 ms apart, from three independent callers —
    ///
    ///   1. `MainTabView.task`, after `loadCurrentUser()`
    ///   2. `HomeView.task(id: vm.currentUser?.id)` → `startRealtimeUpdates()`, whose
    ///      `if groups.isEmpty && archivedGroups.isEmpty` bootstrap still sees an empty list
    ///      because #1 is mid-flight. `currentUser` flipping nil→set is what re-fires the task.
    ///   3. `MainTabView.onReceive(didBecomeActiveNotification)`, which fires on **cold launch**,
    ///      not only on foregrounding
    ///
    /// Home's numbers land when the *last* of the three finishes, which measured 723–973 ms —
    /// the second the balances appear to take. None of the three is wrong on its own; together
    /// they fetch the same data three times.
    ///
    /// A joined caller waits for the running load and sees its result, so pull-to-refresh keeps
    /// spinning until data arrives rather than ending instantly on a dropped request. What it
    /// gives up is small and bounded: a request landing in the last moments of a running load
    /// receives that load's data, fetched a moment before the request.
    ///
    /// - Parameter force: for a caller that *knows* something changed and therefore cannot accept
    ///   a fetch that began before it — the realtime stream is the only one. It joins the running
    ///   load and additionally requires one more pass afterwards, coalesced the same way
    ///   `computeBalances` coalesces (REV-05), so N forced requests during one load cost one extra
    ///   pass rather than N.
    func loadAll(force: Bool = false) async {
        if let existing = inFlightLoad {
            if force { shouldReloadAgain = true }
            AppDiagnostics.log(.balance, "HomeViewModel.loadAll.joined", [("force", force)])
            await existing.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                self.shouldReloadAgain = false
                await self.performLoadAll()
            } while self.shouldReloadAgain
        }
        inFlightLoad = task
        await task.value
        if inFlightLoad == task { inFlightLoad = nil }
    }

    private func performLoadAll() async {
        guard let user = currentUser else {
            AppDiagnostics.log(.balance, "HomeViewModel.loadAll.skipped", [("reason", "no currentUser")])
            return
        }

        AppDiagnostics.log(.balance, "HomeViewModel.loadAll.enter", [
            ("connected", isConnectedProvider()),
            ("groups", groups.count),
            ("isLoading", isLoading)
        ])

        if isConnectedProvider() {
            isLoading = true
            defer { isLoading = false }
            do {
                groups = try await groupService.fetchGroups(for: user.id)
                CacheService.shared.saveGroups(groups)
                indexGroupsForSearch(groups)
                // PERF: archived groups are not shown on Home, so awaiting them before the
                // balances put a whole round trip on the critical path for data nothing on this
                // screen renders. Measured on device before the change: groups 90 ms, archived
                // 85 ms, balances 282 ms, total 458 ms — the archived fetch was ~20% of the wait.
                // Both now run concurrently, so the balances no longer queue behind a list the
                // user cannot see.
                //
                // ⚠️ The end-to-end gain is NOT established. Five cold launches before averaged
                // 421 ms and four after averaged 361 ms, which is consistent with removing an
                // ~88 ms serial step but the samples overlap heavily — at that spread it cannot
                // be distinguished from noise. What is established is that the archived fetch is
                // no longer serialised ahead of the balances. The larger cost is `computeBalances`
                // itself, which is still one round trip per group; a server-side
                // `get_group_balances` RPC is the fix that actually scales.
                async let archived: Void = loadArchivedGroups()
                async let balances: Void = computeBalances(for: user.id)
                _ = await (archived, balances)
                AppDiagnostics.log(.balance, "HomeViewModel.loadAll.success", [
                    ("groups", groups.count),
                    ("owed", "\(totalOwed)"),
                    ("owing", "\(totalOwing)")
                ])
            } catch {
                AppDiagnostics.log(.balance, "HomeViewModel.loadAll.catch", [
                    ("silent", AppError.isSilent(error)),
                    ("connected", isConnectedProvider()),
                    ("error", AppDiagnostics.describe(error))
                ])
                guard !AppError.isSilent(error) else { return }
                // Fall back to cache on network error
                if groups.isEmpty { groups = CacheService.shared.loadGroups() }
                self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
                await computeBalances(for: user.id)
            }
        } else {
            groups = CacheService.shared.loadGroups()
        }
    }

    func refresh() async { await loadAll() }

    func deleteGroup(_ group: BillGroup) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await groupService.deleteGroup(groupId: group.id)
            groups.removeAll { $0.id == group.id }
            // Keep the persistent cache in sync so the deleted group doesn't reappear on cold launch.
            CacheService.shared.saveGroups(groups)
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    func loadArchivedGroups() async {
        guard let user = currentUser else { return }
        do {
            archivedGroups = try await groupService.fetchArchivedGroups(for: user.id)
        } catch {
            AppDiagnostics.log(.balance, "HomeViewModel.loadArchivedGroups.catch", [
                ("silent", AppError.isSilent(error)),
                ("error", AppDiagnostics.describe(error))
            ])
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    func unarchiveGroup(_ group: BillGroup) async {
        // Capture pre-attempt state so both arrays can be restored on failure.
        let originalIndex = archivedGroups.firstIndex(where: { $0.id == group.id })
        let previousGroups = groups
        do {
            var updated = group
            updated.isArchived = false
            _ = try await groupService.updateGroup(updated)
            archivedGroups.removeAll { $0.id == group.id }
            await loadAll()
        } catch {
            // Restore archivedGroups to pre-attempt state.
            if !archivedGroups.contains(where: { $0.id == group.id }) {
                if let index = originalIndex {
                    archivedGroups.insert(group, at: min(index, archivedGroups.count))
                } else {
                    archivedGroups.append(group)
                }
            }
            // Restore groups to pre-attempt state in case loadAll() left it partially loaded.
            groups = previousGroups
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    // MARK: - Realtime

    func startRealtimeUpdates() {
        realtimeTask?.cancel()
        realtimeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let user = self.currentUser else {
                AppDiagnostics.log(.sync, "HomeViewModel.realtime.skipped", [("reason", "no current user")])
                return
            }
            if self.groups.isEmpty && self.archivedGroups.isEmpty {
                await self.loadAll()
            }
            let groupIDs = (self.groups + self.archivedGroups).map(\.id)
            guard let stream = try? await self.groupService.groupChanges(userID: user.id, groupIDs: groupIDs) else { return }
            AppDiagnostics.log(.sync, "HomeViewModel.realtime.subscribed", [
                ("groups", groupIDs.count)
            ])
            for await _ in stream {
                guard !Task.isCancelled else { return }
                AppDiagnostics.log(.sync, "HomeViewModel.realtime.event", [])
                // `force`: the event says a row changed *now*. A load already in flight may have
                // fetched before that commit, so joining it alone could return without the change.
                await self.loadAll(force: true)
            }
        }
    }

    // MARK: - Sample Data

    func createSampleData(userID: UUID) async throws {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let group = try await groupService.createGroup(
            name: "Sample Trip",
            emoji: "🏖️",
            currency: "USD",
            createdBy: userID
        )
        let sampleExpenses: [(String, Decimal, Expense.Category)] = [
            ("Airfare",             240.00, .transport),
            ("Hotel (2 nights)",    180.00, .accommodation),
            ("Dinner at La Palma",   65.00, .food),
        ]
        for (title, amount, category) in sampleExpenses {
            var split = SplitInput(userID: userID, displayName: "You")
            split.amount     = amount
            split.isIncluded = true
            _ = try await expenseService.createExpense(
                groupID: group.id, title: title, amount: amount,
                currency: "USD", payerID: userID, category: category,
                notes: "Sample expense — feel free to delete", splits: [split]
            )
        }
        groups.append(group)
        CacheService.shared.saveGroups(groups)
    }

    // MARK: - Balance + Recent Expenses

    /// Coalesces overlapping recomputes instead of dropping them.
    ///
    /// This used to be `guard !isComputingBalances else { return }` — a request that arrived while
    /// a computation was in flight was thrown away. Harmless while both callers see the same group
    /// list, and wrong the moment they do not, which is exactly what a realtime event produces:
    ///
    ///   1. load #1 reads `groups`, starts computing, and is still fetching
    ///   2. a group appears; load #2 fetches the new list and assigns it
    ///   3. load #2's recompute is dropped, because #1 is still running
    ///   4. #1 finishes and publishes totals for the list it read in step 1
    ///
    /// Home then renders a total that omits a group it is simultaneously listing. Nothing throws
    /// and both `await`s return — the numbers are just wrong. `HomeViewModelOrderingTests` drives
    /// that exact ordering.
    ///
    /// Same shape as `GroupViewModel.computeBalances` (REV-05): the in-flight run re-checks the
    /// flag and goes round again. Note what this does **not** promise — a caller whose request is
    /// coalesced has its `await` return before the recompute it asked for has happened. The
    /// guarantee is that the *last* state wins once everything settles, not that any individual
    /// `await` observes it.
    private func computeBalances(for userID: UUID) async {
        if isComputingBalances {
            shouldRecomputeBalances = true
            return
        }
        isComputingBalances = true
        defer { isComputingBalances = false }
        repeat {
            shouldRecomputeBalances = false
            await performBalanceComputation(for: userID)
        } while shouldRecomputeBalances
    }

    private func performBalanceComputation(for userID: UUID) async {
        var owed             = Decimal.zero
        var owing            = Decimal.zero
        var allEntries:      [RecentEntry]             = []
        var mergedByCurrency:[String: [UUID: Decimal]] = [:]
        var allNames:        [UUID: String]            = [:]

        let groupService = self.groupService
        let expenseService = self.expenseService
        let settlementService = self.settlementService

        // PERF-02: one request for every group's members and balances, instead of three per group.
        // PERF-03: the expense fetches depend only on the group list, **not** on the balances, so
        // they start at the same time as the RPC rather than after it. That is the difference
        // between two sequential round trips and one — PERF-02 alone cut the request count without
        // touching the depth of the critical path, which is why it did not show on the clock.
        let groupsSnapshot = groups
        async let fetchedRows = Self.groupBalanceRows(using: groupService)
        async let fetchedExpenses = Self.expensesForAllGroups(groupsSnapshot, using: expenseService)
        let rowsByGroup = await fetchedRows
        let expensesByGroup = await fetchedExpenses

        await withTaskGroup(of: GroupBalanceData.self) { taskGroup in
            for group in groups {
                let rows = rowsByGroup?[group.id]
                let fetched = expensesByGroup[group.id] ?? ExpenseFetch(expenses: [], loadFailed: true)
                taskGroup.addTask {
                    if let rows, let fromRPC = await Self.balancesFromRows(
                        rows, group: group, userID: userID, expenses: fetched) {
                        return fromRPC
                    }
                    return await Self.fullBalancesInGroup(
                        group,
                        userID: userID,
                        expenses: fetched,
                        groupService: groupService,
                        expenseService: expenseService,
                        settlementService: settlementService
                    )
                }
            }
            for await data in taskGroup {
                owed  += data.owed
                owing += data.owing
                allEntries.append(contentsOf: data.entries)
                for (uid, bal) in data.balances {
                    mergedByCurrency[data.currency, default: [:]][uid, default: .zero] += bal
                }
                allNames.merge(data.names) { _, new in new }
                groupMemberCounts[data.groupID] = data.memberCount
                groupNetBalances[data.groupID]  = data.netBalance
                if data.loadFailed, errorAlert == nil {
                    errorAlert = ErrorAlert(
                        title: "Some balances may be stale",
                        message: "xBill could not refresh one or more groups. Cached data is shown when available."
                    )
                }
            }
        }

        totalOwed      = owed
        totalOwing     = owing
        recentExpenses = allEntries
            .sorted { $0.expense.createdAt > $1.expense.createdAt }
            .prefix(10)
            .map { $0 }

        // Cross-group debt simplification: merge balances across groups per currency
        var suggestions: [SettlementSuggestion] = []
        for (currency, balances) in mergedByCurrency {
            let perCurrency = SplitCalculator.minimizeTransactions(
                balances: balances, names: allNames, currency: currency
            )
            suggestions.append(contentsOf: perCurrency)
        }
        // Only surface suggestions that involve the current user to avoid noise
        crossGroupSuggestions = suggestions.filter {
            $0.fromUserID == userID || $0.toUserID == userID
        }

        let primaryCurrency = mergedByCurrency.count == 1 ? (mergedByCurrency.keys.first ?? "USD") : "USD"
        CacheService.shared.saveBalance(netBalance: netBalance, totalOwed: totalOwed, totalOwing: totalOwing, currency: primaryCurrency)
        reloadWidgets()
    }

    /// One group's expenses, and whether the read failed. A failure falls back to the cache, so
    /// the rows may be stale rather than absent — which is why the flag travels with them.
    private struct ExpenseFetch: Sendable {
        let expenses: [Expense]
        let loadFailed: Bool
    }

    /// `nil` when the RPC is unavailable, which sends every group down the local path. Kept
    /// separate so it can be started concurrently with the expense fetches.
    private static func groupBalanceRows(
        using groupService: any HomeGroupDataProviding
    ) async -> [UUID: [GroupBalanceRow]]? {
        do {
            return Dictionary(grouping: try await groupService.groupBalances(), by: \.groupID)
        } catch {
            AppDiagnostics.log(.balance, "HomeViewModel.groupBalances.catch", [
                ("error", AppDiagnostics.describe(error))
            ])
            return nil
        }
    }

    /// Every group's expenses, fetched concurrently. Needed by Recent Expenses either way, and by
    /// the local balance path when the RPC is unavailable — so it runs regardless, and in parallel
    /// with the RPC rather than behind it.
    private static func expensesForAllGroups(
        _ groups: [BillGroup],
        using expenseService: any HomeExpenseDataProviding
    ) async -> [UUID: ExpenseFetch] {
        await withTaskGroup(of: (UUID, ExpenseFetch).self) { taskGroup in
            for group in groups {
                taskGroup.addTask {
                    do {
                        let expenses = try await expenseService.fetchExpenses(groupID: group.id, limit: nil)
                        CacheService.shared.saveExpenses(expenses, groupID: group.id)
                        return (group.id, ExpenseFetch(expenses: expenses, loadFailed: false))
                    } catch {
                        let cached = CacheService.shared.loadExpenses(groupID: group.id)
                        return (group.id, ExpenseFetch(expenses: cached, loadFailed: true))
                    }
                }
            }
            var result: [UUID: ExpenseFetch] = [:]
            for await (id, fetch) in taskGroup { result[id] = fetch }
            return result
        }
    }

    /// Builds a group's contribution from `get_group_balances()` rows and already-fetched expenses.
    ///
    /// It performs no I/O — everything it needs has been fetched by the time it is called. It stays
    /// `async` only because it is `@MainActor` and the task group's closure is not, so the `await`
    /// is the actor hop rather than a wait on anything.
    ///
    /// Returns `nil` if any balance fails to parse — a malformed number must not be read as zero,
    /// which would silently understate a debt. The caller then falls back to computing it locally.
    ///
    /// `rows` is never empty for a group the caller belongs to: the function joins `group_members`,
    /// so the caller's own row is always present. An empty array therefore means the RPC did not
    /// know about this group, and deserves the local path rather than a confident zero.
    private static func balancesFromRows(
        _ rows: [GroupBalanceRow],
        group: BillGroup,
        userID: UUID,
        expenses fetched: ExpenseFetch
    ) async -> GroupBalanceData? {
        guard !rows.isEmpty else { return nil }

        var balances: [UUID: Decimal] = [:]
        for row in rows {
            guard let value = row.decimalBalance else { return nil }
            balances[row.userID] = value
        }

        let members = rows.map(\.user)
        let expenses = fetched.expenses
        let loadFailed = fetched.loadFailed
        CacheService.shared.saveMembers(members, groupID: group.id)

        let net   = balances[userID] ?? .zero
        let owed  = net > .zero ? net  : .zero
        let owing = net < .zero ? -net : .zero
        return GroupBalanceData(
            groupID: group.id, owed: owed, owing: owing, netBalance: net,
            memberCount: members.filter(\.isActive).count,
            entries: expenses.map { RecentEntry(expense: $0, members: members) },
            // The group's own currency, matching the local path. The RPC returns it too; they are
            // the same column.
            currency: group.currency,
            balances: balances,
            names: Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) }),
            loadFailed: loadFailed
        )
    }

    /// Splits for expenses that have already been fetched. Used only by the local fallback path.
    private static func splits(
        for expenses: [Expense],
        using expenseService: any HomeExpenseDataProviding
    ) async -> (splits: [UUID: [Split]], loadFailed: Bool) {
        do {
            return (try await SplitCalculator.fetchSplitsMap(for: expenses, using: expenseService), false)
        } catch {
            return ([:], true)
        }
    }

    /// A members failure deliberately does **not** raise `loadFailed`: names going missing shows as
    /// missing names, not as a wrong number.
    private static func members(
        for group: BillGroup,
        using groupService: any HomeGroupDataProviding
    ) async -> [User] {
        do {
            let members = try await groupService.fetchMembers(groupID: group.id, includeInactive: true)
            CacheService.shared.saveMembers(members, groupID: group.id)
            return members
        } catch {
            return CacheService.shared.loadMembers(groupID: group.id)
        }
    }

    /// Unlike a failed splits fetch (which collapses balances toward zero), a failed settlements
    /// fetch makes every split count as unpaid — the largest possible wrong number, and silently so
    /// unless this feeds `loadFailed` in the caller (IMP-2).
    private static func settlements(
        for group: BillGroup,
        using settlementService: any SettlementDataProviding
    ) async -> (settlements: [Settlement], loadFailed: Bool) {
        do {
            return (try await settlementService.fetchSettlements(groupID: group.id), false)
        } catch {
            return ([], true)
        }
    }

    /// One group's contribution to the home-screen totals.
    ///
    /// PERF: these four fetches used to run **one after another** — expenses, then members, then
    /// splits, then settlements — for every group. Two groups meant eight round trips with only
    /// the groups themselves overlapping, and it grew with each group joined.
    ///
    /// Only splits depends on expenses. Members and settlements depend on nothing, so the chain is
    /// really `expenses → splits` alongside `members` alongside `settlements`: two sequential waits
    /// instead of four. Each branch keeps its own `do`/`catch` and its own cache fallback, so the
    /// failure behaviour is unchanged — in particular a members failure still does **not** raise
    /// `loadFailed`, while any of the other three does.
    ///
    /// The next step, if this is still not fast enough, is a server-side `get_group_balances` that
    /// makes it one request for all groups rather than four per group. That is a schema change and
    /// deliberately not bundled here.
    private static func fullBalancesInGroup(
        _ group: BillGroup,
        userID: UUID,
        expenses fetched: ExpenseFetch,
        groupService: any HomeGroupDataProviding,
        expenseService: any HomeExpenseDataProviding,
        settlementService: any SettlementDataProviding
    ) async -> GroupBalanceData {
        let expenses = fetched.expenses
        let loadFailed = fetched.loadFailed
        async let fetchedSplits      = splits(for: expenses, using: expenseService)
        async let fetchedMembers     = members(for: group, using: groupService)
        async let fetchedSettlements = settlements(for: group, using: settlementService)

        let (splitsMap, splitLoadFailed) = await fetchedSplits
        let members = await fetchedMembers
        let (settlements, settlementLoadFailed) = await fetchedSettlements

        let balances  = SplitCalculator.netBalances(expenses: expenses, splits: splitsMap, settlements: settlements)
        let net       = balances[userID] ?? .zero
        let owed      = net > .zero ? net  : .zero
        let owing     = net < .zero ? -net : .zero
        let entries   = expenses.map { RecentEntry(expense: $0, members: members) }
        let names     = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })
        let data      = GroupBalanceData(groupID: group.id, owed: owed, owing: owing, netBalance: net,
                                         memberCount: members.filter(\.isActive).count, entries: entries,
                                         currency: group.currency, balances: balances, names: names,
                                         loadFailed: loadFailed || splitLoadFailed || settlementLoadFailed)
        return data
    }
}

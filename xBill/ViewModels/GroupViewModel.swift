//
//  GroupViewModel.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class GroupViewModel {

    // MARK: - State

    var group: BillGroup
    var members: [User] = []
    var expenses: [Expense] = []
    var balances: [UUID: Decimal] = [:]
    var settlementSuggestions: [SettlementSuggestion] = []
    var isLoading: Bool = false
    var isLoadingBalances: Bool = false
    var hasLoadedBalances: Bool = false
    var balanceLoadFailed: Bool = false
    var hasKnownNonEmptyExpenses: Bool = false
    var errorAlert: ErrorAlert?

    private var splitsMap: [UUID: [Split]] = [:]
    @ObservationIgnored private var locallyConfirmedSettledSplitIDs: Set<UUID> = []
    @ObservationIgnored private var locallyCreatedExpenses: [UUID: Expense] = [:]
    @ObservationIgnored private var isComputingBalances = false
    @ObservationIgnored private var shouldRecomputeBalances = false
    private let logger = Logger(subsystem: "com.vijaygoyal.xbill", category: "GroupViewModel")
    private let groupService = GroupService.shared
    private let expenseService = ExpenseService.shared

    init(group: BillGroup) {
        self.group = group
        let cachedMembers = CacheService.shared.loadMembers(groupID: group.id)
        let cachedExpenses = CacheService.shared.loadExpenses(groupID: group.id)
        self.members = cachedMembers
        self.expenses = cachedExpenses
        self.hasKnownNonEmptyExpenses = !cachedExpenses.isEmpty || CacheService.shared.hasKnownNonEmptyExpenses(groupID: group.id)
    }

    // MARK: - Computed

    var memberNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })
    }

    var sortedExpenses: [Expense] {
        expenses.sorted { $0.createdAt > $1.createdAt }
    }

    var activeMembers: [User] {
        members.filter(\.isActive)
    }

    var canChangeCurrency: Bool {
        expenses.isEmpty
    }

    func balance(for userID: UUID) -> Decimal {
        balances[userID] ?? .zero
    }

    // MARK: - Load

    func load(showError: Bool = true) async {
        guard !isLoading else {
            AppDiagnostics.log(.balance, "GroupViewModel.load.skipped", [
                ("group", group.name),
                ("reason", "already loading")
            ])
            return
        }
        isLoading = true
        defer { isLoading = false }

        AppDiagnostics.log(.balance, "GroupViewModel.load.enter", [
            ("group", group.name),
            ("groupID", group.id.uuidString),
            ("showError", showError),
            ("connected", NetworkMonitor.shared.isConnected),
            ("expenses", expenses.count),
            ("cachedExpenses", CacheService.shared.loadExpenses(groupID: group.id).count),
            ("suggestions", settlementSuggestions.count),
            ("hasLoadedBalances", hasLoadedBalances),
            ("balanceLoadFailed", balanceLoadFailed),
            ("hasKnownNonEmpty", hasKnownNonEmptyExpenses)
        ])

        if NetworkMonitor.shared.isConnected {
            do {
                let groupID = group.id
                let groupService = groupService
                let expenseService = expenseService
                let (fetchedMembers, fetchedExpenses) = try await withTimeout(duration: .seconds(12)) {
                    async let membersTask = groupService.fetchMembers(groupID: groupID, includeInactive: true)
                    async let expensesTask = expenseService.fetchExpenses(groupID: groupID)
                    return try await (membersTask, expensesTask)
                }
                members  = fetchedMembers
                applyFetchedExpenses(fetchedExpenses)
                hasKnownNonEmptyExpenses = hasKnownNonEmptyExpenses || !expenses.isEmpty
                CacheService.shared.saveMembers(fetchedMembers, groupID: group.id)
                CacheService.shared.saveExpenses(expenses, groupID: group.id)
                await computeBalances()
                AppDiagnostics.log(.balance, "GroupViewModel.load.success", [
                    ("group", group.name),
                    ("expenses", expenses.count),
                    ("suggestions", settlementSuggestions.count),
                    ("hasLoadedBalances", hasLoadedBalances),
                    ("balanceLoadFailed", balanceLoadFailed)
                ])
            } catch {
                AppDiagnostics.log(.balance, "GroupViewModel.load.catch", [
                    ("group", group.name),
                    ("showError", showError),
                    ("silent", AppError.isSilent(error)),
                    ("connected", NetworkMonitor.shared.isConnected),
                    ("error", AppDiagnostics.describe(error))
                ])
                guard !AppError.isSilent(error) else { return }
                // Unconditionally restore from cache on any network error — a partial
                // in-flight fetch may have written one array but not the other.
                let cachedMembers  = CacheService.shared.loadMembers(groupID: group.id)
                let cachedExpenses = CacheService.shared.loadExpenses(groupID: group.id)
                if !cachedMembers.isEmpty  { members  = cachedMembers }
                if !cachedExpenses.isEmpty { expenses = cachedExpenses }
                hasKnownNonEmptyExpenses = hasKnownNonEmptyExpenses || !cachedExpenses.isEmpty || CacheService.shared.hasKnownNonEmptyExpenses(groupID: group.id)
                if showError {
                    self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
                }
                await computeBalances()
            }
        } else {
            members  = CacheService.shared.loadMembers(groupID: group.id)
            expenses = CacheService.shared.loadExpenses(groupID: group.id)
            hasKnownNonEmptyExpenses = hasKnownNonEmptyExpenses || !expenses.isEmpty || CacheService.shared.hasKnownNonEmptyExpenses(groupID: group.id)
            await computeBalances()
        }
    }

    func refresh(showError: Bool = true) async { await load(showError: showError) }

    func recordCreatedExpense(_ expense: Expense) {
        locallyCreatedExpenses[expense.id] = expense
        if !expenses.contains(where: { $0.id == expense.id }) {
            expenses.append(expense)
        }
    }

    private func applyFetchedExpenses(_ fetchedExpenses: [Expense]) {
        if fetchedExpenses.isEmpty {
            let cachedExpenses = CacheService.shared.loadExpenses(groupID: group.id)
            if !expenses.isEmpty {
                hasKnownNonEmptyExpenses = true
                balanceLoadFailed = true
                logger.warning("Keeping previous expenses because reload returned an empty expense list for a non-empty group")
                return
            }
            if !cachedExpenses.isEmpty {
                hasKnownNonEmptyExpenses = true
                balanceLoadFailed = true
                logger.warning("Restoring cached expenses because reload returned an empty expense list")
                expenses = cachedExpenses
                return
            }
            if hasKnownNonEmptyExpenses || CacheService.shared.hasKnownNonEmptyExpenses(groupID: group.id) {
                hasKnownNonEmptyExpenses = true
                balanceLoadFailed = true
                logger.warning("Ignoring empty expense reload for a group previously known to have expenses")
                return
            }
        }

        var mergedExpenses = fetchedExpenses
        for expense in locallyCreatedExpenses.values where !mergedExpenses.contains(where: { $0.id == expense.id }) {
            mergedExpenses.append(expense)
        }
        for expense in fetchedExpenses {
            locallyCreatedExpenses.removeValue(forKey: expense.id)
        }
        expenses = mergedExpenses
        hasKnownNonEmptyExpenses = hasKnownNonEmptyExpenses || !mergedExpenses.isEmpty
    }

    // MARK: - Balances

    private func computeBalances() async {
        if isComputingBalances {
            shouldRecomputeBalances = true
            return
        }
        isComputingBalances = true
        isLoadingBalances = true
        balanceLoadFailed = false
        defer { isComputingBalances = false }
        defer { isLoadingBalances = false }

        repeat {
            shouldRecomputeBalances = false
            do {
                let currentExpenses = expenses
                let expenseService = expenseService
                var fetchedSplitsMap = try await withTimeout(duration: .seconds(12)) {
                    try await SplitCalculator.fetchSplitsMap(for: currentExpenses, using: expenseService)
                }
                // Supabase can briefly return a pre-update snapshot immediately after
                // an update. Preserve confirmed local writes across that read so a
                // lifecycle refresh cannot resurrect a row the user just settled.
                for splitID in locallyConfirmedSettledSplitIDs {
                    for expenseID in fetchedSplitsMap.keys {
                        guard var expenseSplits = fetchedSplitsMap[expenseID],
                              let index = expenseSplits.firstIndex(where: { $0.id == splitID }) else {
                            continue
                        }
                        expenseSplits[index].isSettled = true
                        fetchedSplitsMap[expenseID] = expenseSplits
                    }
                }
                splitsMap = fetchedSplitsMap
            } catch {
                AppDiagnostics.log(.balance, "GroupViewModel.computeBalances.catch", [
                    ("group", group.name),
                    ("expenses", expenses.count),
                    ("splitsMap", splitsMap.count),
                    ("connected", NetworkMonitor.shared.isConnected),
                    ("error", AppDiagnostics.describe(error))
                ])
                guard !expenses.isEmpty else { return }
                guard !splitsMap.isEmpty else {
                    balanceLoadFailed = true
                    logger.error("Split loading failed with no previous split map: \(error.localizedDescription, privacy: .public)")
                    return
                }
                balanceLoadFailed = true
                logger.warning("Keeping previous split map because split loading failed: \(error.localizedDescription, privacy: .public)")
            }
            let rawBalances = SplitCalculator.netBalances(expenses: expenses, splits: splitsMap)
            balances = rawBalances
            settlementSuggestions = SplitCalculator.directSettlementSuggestions(
                expenses: expenses,
                splits: splitsMap,
                names: memberNames,
                currency: group.currency
            )
            hasLoadedBalances = true
        } while shouldRecomputeBalances
    }

    // MARK: - Members

    func addMember(userId: UUID) async {
        do {
            try await groupService.addMember(groupId: group.id, userId: userId)
            await load()
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    func removeMember(userID: UUID) async {
        do {
            try await groupService.removeMember(groupId: group.id, userId: userID)
            await load()
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    func updateGroupDetails(name: String, emoji: String, currency: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorAlert = ErrorAlert(title: "Missing Group Name", message: "Enter a group name before saving.")
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            var updated = group
            updated.name = trimmedName
            updated.emoji = emoji
            if currency != group.currency {
                guard canChangeCurrency else {
                    throw AppError.validationFailed("Currency cannot be changed after expenses have been added to this group.")
                }
                updated.currency = currency
            }
            group = try await groupService.updateGroup(updated)
            var cached = CacheService.shared.loadGroups()
            if let index = cached.firstIndex(where: { $0.id == group.id }) {
                cached[index] = group
                CacheService.shared.saveGroups(cached)
            }
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    // MARK: - Archive

    func archiveGroup() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var updated = group
            updated.isArchived = true
            group = try await groupService.updateGroup(updated)
            // Remove from active-groups cache
            var active = CacheService.shared.loadGroups()
            active.removeAll { $0.id == group.id }
            CacheService.shared.saveGroups(active)
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    func unarchiveGroup() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var updated = group
            updated.isArchived = false
            group = try await groupService.updateGroup(updated)
            var cached = CacheService.shared.loadGroups()
            if !cached.contains(where: { $0.id == group.id }) {
                cached.append(group)
                CacheService.shared.saveGroups(cached)
            }
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    // MARK: - Recurring Instances

    /// Creates new expense instances for any recurring expenses that are due,
    /// then advances (clears) the template's next_occurrence_date.
    /// Only acts on expenses where the current user is the payer (RPC constraint).
    func createDueRecurringInstances(currentUserID: UUID) async {
        guard NetworkMonitor.shared.isConnected else { return }
        do {
            let dueExpenses = try await expenseService.fetchDueRecurringExpenses(groupID: group.id)
            guard !dueExpenses.isEmpty else { return }

            for expense in dueExpenses {
                guard expense.recurrence != .none,
                      let nextDate = expense.nextOccurrenceDate else { continue }

                guard let newNextDate = expense.recurrence.nextDate(from: nextDate) else { continue }

                do {
                    _ = try await expenseService.createRecurringInstance(
                        templateID: expense.id,
                        expectedNextOccurrence: nextDate,
                        newNextOccurrence: newNextDate
                    )
                } catch {
                    Logger(subsystem: "com.vijaygoyal.xbill", category: "Recurring")
                        .fault("Failed to create recurring instance for expense \(expense.id): \(error)")
                }
            }

            await load(showError: false)
        } catch {
            guard !AppError.isSilent(error) else { return }
            // Recurring maintenance is opportunistic and should not block the group screen.
            // A later refresh will retry it without presenting a misleading payment/load error.
            AppDiagnostics.log(.balance, "GroupViewModel.createDueRecurringInstances.catch", [
                ("group", group.name),
                ("error", AppDiagnostics.describe(error))
            ])
            logger.warning("Recurring expense maintenance skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Settle Up

    func deleteExpense(_ expense: Expense) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await expenseService.deleteExpense(id: expense.id)
            expenses.removeAll { $0.id == expense.id }
            splitsMap.removeValue(forKey: expense.id)
            await computeBalances()
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    func updateExpense(_ updated: Expense) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let saved = try await expenseService.updateExpense(updated)
            if let i = expenses.firstIndex(where: { $0.id == saved.id }) {
                expenses[i] = saved
            }
            await computeBalances()
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    func recordSettlement(_ suggestion: SettlementSuggestion) async {
        isLoading = true
        defer { isLoading = false }

        AppDiagnostics.log(.balance, "GroupViewModel.recordSettlement.enter", [
            ("group", group.name),
            ("from", suggestion.fromUserID.uuidString),
            ("to", suggestion.toUserID.uuidString),
            ("amount", suggestion.amount)
        ])

        do {
            // Fetch fresh splits for expenses paid by the creditor to avoid stale splitsMap data.
            let relevantExpenseIDs = expenses.compactMap { expense -> UUID? in
                guard let payerID = expense.payerID, payerID == suggestion.toUserID else { return nil }
                return expense.id
            }
            let freshSplits = try await expenseService.fetchSplits(expenseIDs: relevantExpenseIDs)
            let freshSplitsMap = Dictionary(grouping: freshSplits, by: \.expenseID)

            // Collect whole matching splits up to the suggested amount. Splits do not support
            // partial settlement, so never mark more debt settled than the user confirmed.
            let candidateSplits: [Split] = freshSplitsMap
                .sorted { $0.key.uuidString < $1.key.uuidString }
                .flatMap { (_, splits) in
                    splits
                        .filter { $0.userID == suggestion.fromUserID && !$0.isSettled }
                        .sorted { $0.id.uuidString < $1.id.uuidString }
                }

            var remaining = suggestion.amount
            let epsilon = Decimal(string: "0.005") ?? Decimal(5) / Decimal(1000)
            var splitsToSettle: [Split] = []
            for split in candidateSplits {
                guard split.amount <= remaining + epsilon else { continue }
                splitsToSettle.append(split)
                remaining -= split.amount
                if remaining <= epsilon { break }
            }
            guard !splitsToSettle.isEmpty, remaining <= epsilon else {
                AppDiagnostics.log(.balance, "GroupViewModel.recordSettlement.unmatched", [
                    ("group", group.name),
                    ("candidateSplits", candidateSplits.count),
                    ("remaining", remaining)
                ])
                throw AppError.validationFailed(
                    "This settlement cannot be matched to the current expense splits. Refresh the group and try again."
                )
            }

            try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                for split in splitsToSettle {
                    taskGroup.addTask {
                        try await self.expenseService.settleSplit(id: split.id)
                    }
                }
                try await taskGroup.waitForAll()
            }

            AppDiagnostics.log(.balance, "GroupViewModel.recordSettlement.splitsUpdated", [
                ("group", group.name),
                ("count", splitsToSettle.count),
                ("amount", suggestion.amount)
            ])

            locallyConfirmedSettledSplitIDs.formUnion(splitsToSettle.map(\.id))

            // Reflect confirmed writes locally before the network reload. This keeps
            // Settle Up truthful if the immediate read-after-write returns an older
            // snapshot or a competing lifecycle refresh is cancelled.
            for settledSplit in splitsToSettle {
                guard var expenseSplits = splitsMap[settledSplit.expenseID],
                      let index = expenseSplits.firstIndex(where: { $0.id == settledSplit.id }) else {
                    continue
                }
                expenseSplits[index].isSettled = true
                expenseSplits[index].settledAt = Date()
                splitsMap[settledSplit.expenseID] = expenseSplits
            }
            balances = SplitCalculator.netBalances(expenses: expenses, splits: splitsMap)
            settlementSuggestions = SplitCalculator.directSettlementSuggestions(
                expenses: expenses,
                splits: splitsMap,
                names: memberNames,
                currency: group.currency
            )

            let note = NotificationItem.settlement(
                suggestion: suggestion,
                groupName: group.name,
                groupEmoji: group.emoji
            )
            NotificationStore.shared.merge([note], userID: suggestion.fromUserID)

            // Await the notification inline; isSaved drives sheet dismissal, not isLoading.
            if CacheService.defaults.bool(forKey: NotificationService.settlementPreferenceKey) {
                await expenseService.notifySettlementRecorded(
                    settlementID: suggestion.id,
                    groupID:      group.id,
                    toUserID:     suggestion.toUserID,
                    amount:       suggestion.amount,
                    currency:     suggestion.currency
                )
            }

            // `load()` intentionally skips while `isLoading` is true. Clear the
            // settlement operation's loading state before reloading so the just-updated
            // split is reflected immediately in Settle Up instead of leaving the old row
            // visible until a later screen refresh.
            isLoading = false
            await load()
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }
}

internal func withTimeout<T: Sendable>(
    duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: duration)
            throw AppError.serverError("The request timed out. Check your connection and try again.")
        }

        guard let result = try await group.next() else {
            throw AppError.serverError("The request timed out. Check your connection and try again.")
        }
        group.cancelAll()
        return result
    }
}

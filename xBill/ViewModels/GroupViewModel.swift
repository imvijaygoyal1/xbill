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
    var errorAlert: ErrorAlert?

    private var splitsMap: [UUID: [Split]] = [:]
    @ObservationIgnored private var isComputingBalances = false
    @ObservationIgnored private var shouldRecomputeBalances = false
    private let groupService = GroupService.shared
    private let expenseService = ExpenseService.shared

    init(group: BillGroup) {
        self.group = group
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

    func load() async {
        isLoading = true
        defer { isLoading = false }

        if NetworkMonitor.shared.isConnected {
            do {
                async let membersTask  = groupService.fetchMembers(groupID: group.id, includeInactive: true)
                async let expensesTask = expenseService.fetchExpenses(groupID: group.id)
                let (fetchedMembers, fetchedExpenses) = try await (membersTask, expensesTask)
                members  = fetchedMembers
                expenses = fetchedExpenses
                CacheService.shared.saveMembers(fetchedMembers, groupID: group.id)
                CacheService.shared.saveExpenses(fetchedExpenses, groupID: group.id)
                await computeBalances()
            } catch {
                guard !AppError.isSilent(error) else { return }
                // Unconditionally restore from cache on any network error — a partial
                // in-flight fetch may have written one array but not the other.
                let cachedMembers  = CacheService.shared.loadMembers(groupID: group.id)
                let cachedExpenses = CacheService.shared.loadExpenses(groupID: group.id)
                if !cachedMembers.isEmpty  { members  = cachedMembers }
                if !cachedExpenses.isEmpty { expenses = cachedExpenses }
                self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
                await computeBalances()
            }
        } else {
            members  = CacheService.shared.loadMembers(groupID: group.id)
            expenses = CacheService.shared.loadExpenses(groupID: group.id)
            await computeBalances()
        }
    }

    func refresh() async { await load() }

    // MARK: - Balances

    private func computeBalances() async {
        if isComputingBalances {
            shouldRecomputeBalances = true
            return
        }
        isComputingBalances = true
        defer { isComputingBalances = false }

        repeat {
            shouldRecomputeBalances = false
            splitsMap = await SplitCalculator.fetchSplitsMap(for: expenses, using: expenseService)
            let rawBalances = SplitCalculator.netBalances(expenses: expenses, splits: splitsMap)
            balances = rawBalances
            settlementSuggestions = SplitCalculator.minimizeTransactions(
                balances: rawBalances,
                names: memberNames,
                currency: group.currency
            )
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

            await load()
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
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

        do {
            // Fetch fresh splits for expenses paid by the creditor to avoid stale splitsMap data.
            let relevantExpenseIDs = expenses.compactMap { expense -> UUID? in
                guard let payerID = expense.payerID, payerID == suggestion.toUserID else { return nil }
                return expense.id
            }
            var freshSplitsMap: [UUID: [Split]] = [:]
            await withTaskGroup(of: (UUID, [Split]?).self) { taskGroup in
                for expenseID in relevantExpenseIDs {
                    taskGroup.addTask {
                        let splits = try? await self.expenseService.fetchSplits(expenseID: expenseID)
                        return (expenseID, splits)
                    }
                }
                for await (expenseID, splits) in taskGroup {
                    freshSplitsMap[expenseID] = splits ?? []
                }
            }

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

            let note = NotificationItem.settlement(
                suggestion: suggestion,
                groupName: group.name,
                groupEmoji: group.emoji
            )
            NotificationStore.shared.merge([note])

            // Await the notification inline; isSaved drives sheet dismissal, not isLoading.
            if CacheService.defaults.bool(forKey: NotificationService.settlementPreferenceKey) {
                await expenseService.notifySettlementRecorded(
                    settlementID: suggestion.id,
                    groupID:      group.id,
                    groupName:    group.name,
                    fromUserID:   suggestion.fromUserID,
                    fromName:     suggestion.fromName,
                    toUserID:     suggestion.toUserID,
                    amount:       suggestion.amount,
                    currency:     suggestion.currency
                )
            }

            await load()
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }
}

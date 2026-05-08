//
//  GroupViewModel.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Observation

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

    func balance(for userID: UUID) -> Decimal {
        balances[userID] ?? .zero
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }

        if NetworkMonitor.shared.isConnected {
            do {
                async let membersTask  = groupService.fetchMembers(groupID: group.id)
                async let expensesTask = expenseService.fetchExpenses(groupID: group.id)
                let (fetchedMembers, fetchedExpenses) = try await (membersTask, expensesTask)
                members  = fetchedMembers
                expenses = fetchedExpenses
                CacheService.shared.saveMembers(fetchedMembers, groupID: group.id)
                CacheService.shared.saveExpenses(fetchedExpenses, groupID: group.id)
                await computeBalances()
            } catch {
                guard !AppError.isSilent(error) else { return }
                // Fall back to cache on network error
                if members.isEmpty  { members  = CacheService.shared.loadMembers(groupID: group.id) }
                if expenses.isEmpty { expenses = CacheService.shared.loadExpenses(groupID: group.id) }
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
        // Fetch all splits in parallel instead of serially to avoid blocking MainActor.
        var map: [UUID: [Split]] = [:]
        await withTaskGroup(of: (UUID, [Split]?).self) { taskGroup in
            for expense in expenses {
                taskGroup.addTask {
                    let splits = try? await self.expenseService.fetchSplits(expenseID: expense.id)
                    return (expense.id, splits)
                }
            }
            for await (expenseID, splits) in taskGroup {
                if let splits { map[expenseID] = splits }
            }
        }
        splitsMap = map
        let rawBalances = SplitCalculator.netBalances(expenses: expenses, splits: splitsMap)
        balances = rawBalances
        settlementSuggestions = SplitCalculator.minimizeTransactions(
            balances: rawBalances,
            names: memberNames,
            currency: group.currency
        )
    }

    // MARK: - Members

    func addMember(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await groupService.addMember(groupId: group.id, userId: userId)
            await load()
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    func removeMember(userID: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await groupService.removeMember(groupId: group.id, userId: userID)
            await load()
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
            let dueExpenses = try await expenseService.fetchDueRecurringExpenses(
                groupID: group.id,
                payerID: currentUserID
            )
            guard !dueExpenses.isEmpty else { return }

            for expense in dueExpenses {
                // Skip if the expense has no payer (deleted user) or no next date
                guard expense.recurrence != .none,
                      let nextDate = expense.nextOccurrenceDate,
                      let payerID  = expense.payerID else { continue }

                let existingSplits = (try? await expenseService.fetchSplits(expenseID: expense.id)) ?? []
                let splitInputs = existingSplits.map { SplitInput(from: $0) }
                guard !splitInputs.isEmpty else { continue }

                let newNextDate = expense.recurrence.nextDate(from: nextDate)

                // New instance is a one-off snapshot — it must NOT inherit recurrence or
                // a next date, otherwise it would spawn further instances indefinitely.
                _ = try await expenseService.createExpense(
                    groupID:             expense.groupID,
                    title:               expense.title,
                    amount:              expense.amount,
                    currency:            expense.currency,
                    payerID:             payerID,
                    category:            expense.category,
                    notes:               expense.notes,
                    splits:              splitInputs,
                    originalAmount:      expense.originalAmount,
                    originalCurrency:    expense.originalCurrency,
                    recurrence:          .none,
                    nextOccurrenceDate:  nil
                )

                // Advance the template to the next cycle date (do NOT null it out).
                try await expenseService.setNextOccurrenceDate(newNextDate, expenseID: expense.id)
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

            // Collect unsettled splits where the debtor owes the creditor.
            let splitsToSettle: [Split] = freshSplitsMap.flatMap { (_, splits) in
                splits.filter { $0.userID == suggestion.fromUserID && !$0.isSettled }
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
            if UserDefaults.standard.bool(forKey: "prefPushSettlement") {
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

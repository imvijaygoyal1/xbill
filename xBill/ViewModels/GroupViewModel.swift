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
                SpotlightService.indexExpenses(fetchedExpenses, groupName: group.name, groupEmoji: group.emoji)
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
        var map: [UUID: [Split]] = [:]
        for expense in expenses {
            if let splits = try? await expenseService.fetchSplits(expenseID: expense.id) {
                map[expense.id] = splits
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
            var cached = CacheService.shared.loadGroups()
            cached.removeAll { $0.id == group.id }
            CacheService.shared.saveGroups(cached)
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
                guard expense.recurrence != .none,
                      let nextDate = expense.nextOccurrenceDate else { continue }

                let existingSplits = (try? await expenseService.fetchSplits(expenseID: expense.id)) ?? []
                let splitInputs = existingSplits.map { SplitInput(from: $0) }
                guard !splitInputs.isEmpty else { continue }

                let newNextDate = expense.recurrence.nextDate(from: nextDate)

                _ = try await expenseService.createExpense(
                    groupID:             expense.groupID,
                    title:               expense.title,
                    amount:              expense.amount,
                    currency:            expense.currency,
                    payerID:             expense.payerID,
                    category:            expense.category,
                    notes:               expense.notes,
                    splits:              splitInputs,
                    originalAmount:      expense.originalAmount,
                    originalCurrency:    expense.originalCurrency,
                    recurrence:          expense.recurrence,
                    nextOccurrenceDate:  newNextDate
                )

                try await expenseService.clearNextOccurrenceDate(expenseID: expense.id)
            }

            await load()
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    // MARK: - Settle Up

    func deleteExpense(_ expense: Expense) async {
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
            // Collect all unsettled splits where:
            //   - the debtor (fromUser) owes money
            //   - the expense was paid by the creditor (toUser)
            let splitsToSettle: [Split] = splitsMap.flatMap { (expenseID, splits) -> [Split] in
                guard let expense = expenses.first(where: { $0.id == expenseID }),
                      expense.payerID == suggestion.toUserID else { return [] }
                return splits.filter { $0.userID == suggestion.fromUserID && !$0.isSettled }
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

            Task {
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

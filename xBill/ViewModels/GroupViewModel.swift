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
    var error: AppError?

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
        error = nil
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
                // Fall back to cache on network error
                if members.isEmpty  { members  = CacheService.shared.loadMembers(groupID: group.id) }
                if expenses.isEmpty { expenses = CacheService.shared.loadExpenses(groupID: group.id) }
                self.error = AppError.from(error)
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
        error = nil
        defer { isLoading = false }
        do {
            try await groupService.addMember(groupId: group.id, userId: userId)
            await load()
        } catch {
            self.error = AppError.from(error)
        }
    }

    func removeMember(userID: UUID) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await groupService.removeMember(groupId: group.id, userId: userID)
            await load()
        } catch {
            self.error = AppError.from(error)
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
            self.error = AppError.from(error)
        }
    }

    func updateExpense(_ updated: Expense) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let saved = try await expenseService.updateExpense(updated)
            if let i = expenses.firstIndex(where: { $0.id == saved.id }) {
                expenses[i] = saved
            }
            await computeBalances()
        } catch {
            self.error = AppError.from(error)
        }
    }

    func recordSettlement(_ suggestion: SettlementSuggestion) async {
        isLoading = true
        error = nil
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

            await load()
        } catch {
            self.error = AppError.from(error)
        }
    }
}

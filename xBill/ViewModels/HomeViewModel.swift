import Foundation
import Observation
import SwiftUI

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
    var isLoading: Bool = false
    var error: AppError?

    struct RecentEntry: Identifiable, Sendable {
        var id: UUID { expense.id }
        let expense: Expense
        let members: [User]
    }

    private let groupService = GroupService.shared
    private let expenseService = ExpenseService.shared
    private let auth = AuthService.shared

    // MARK: - Computed

    var netBalance: Decimal { totalOwed - totalOwing }

    // MARK: - Load

    func loadCurrentUser() async {
        do {
            currentUser = try await auth.currentUser()
        } catch {
            self.error = AppError.from(error)
        }
    }

    func loadAll() async {
        guard let user = currentUser else { return }

        if NetworkMonitor.shared.isConnected {
            isLoading = true
            defer { isLoading = false }
            do {
                groups = try await groupService.fetchGroups(for: user.id)
                CacheService.shared.saveGroups(groups)
                SpotlightService.indexGroups(groups)
                await computeBalances(for: user.id)
            } catch {
                guard !(error is CancellationError) else { return }
                // Fall back to cache on network error
                if groups.isEmpty { groups = CacheService.shared.loadGroups() }
                self.error = AppError.from(error)
            }
        } else {
            groups = CacheService.shared.loadGroups()
        }
    }

    func refresh() async { await loadAll() }

    func deleteGroup(_ group: BillGroup) async {
        do {
            try await groupService.deleteGroup(groupId: group.id)
            groups.removeAll { $0.id == group.id }
        } catch {
            self.error = AppError.from(error)
        }
    }

    func loadArchivedGroups() async {
        guard let user = currentUser else { return }
        do {
            archivedGroups = try await groupService.fetchArchivedGroups(for: user.id)
        } catch {
            self.error = AppError.from(error)
        }
    }

    func unarchiveGroup(_ group: BillGroup) async {
        do {
            var updated = group
            updated.isArchived = false
            _ = try await groupService.updateGroup(updated)
            archivedGroups.removeAll { $0.id == group.id }
            await loadAll()
        } catch {
            self.error = AppError.from(error)
        }
    }

    // MARK: - Realtime

    func startRealtimeUpdates() async {
        guard let user = currentUser else { return }
        guard let stream = try? await groupService.groupChanges(userID: user.id) else { return }
        for await _ in stream {
            await loadAll()
        }
    }

    // MARK: - Balance + Recent Expenses

    private func computeBalances(for userID: UUID) async {
        var owed  = Decimal.zero
        var owing = Decimal.zero
        var allEntries: [RecentEntry] = []

        await withTaskGroup(of: (Decimal, Decimal, [RecentEntry]).self) { taskGroup in
            for group in groups {
                taskGroup.addTask {
                    await self.balancesInGroup(group, userID: userID)
                }
            }
            for await (o, ow, entries) in taskGroup {
                owed  += o
                owing += ow
                allEntries.append(contentsOf: entries)
            }
        }

        totalOwed      = owed
        totalOwing     = owing
        recentExpenses = allEntries
            .sorted { $0.expense.createdAt > $1.expense.createdAt }
            .prefix(10)
            .map { $0 }
    }

    private func balancesInGroup(_ group: BillGroup, userID: UUID) async -> (Decimal, Decimal, [RecentEntry]) {
        guard let expenses = try? await expenseService.fetchExpenses(groupID: group.id) else {
            return (.zero, .zero, [])
        }
        let members = (try? await groupService.fetchMembers(groupID: group.id)) ?? []
        var splitsMap: [UUID: [Split]] = [:]
        for expense in expenses {
            if let splits = try? await expenseService.fetchSplits(expenseID: expense.id) {
                splitsMap[expense.id] = splits
            }
        }
        let net   = SplitCalculator.netBalances(expenses: expenses, splits: splitsMap)[userID] ?? .zero
        let owed  = net > .zero ? net  : .zero
        let owing = net < .zero ? -net : .zero
        let entries = expenses.map { RecentEntry(expense: $0, members: members) }
        return (owed, owing, entries)
    }
}

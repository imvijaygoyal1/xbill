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
    @ObservationIgnored private var realtimeTask: Task<Void, Never>?
    @ObservationIgnored private var groupBalancesCache: [UUID: GroupBalanceData] = [:]

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
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
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
                await loadArchivedGroups()
                await computeBalances(for: user.id)
            } catch {
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
            guard let user = self.currentUser else { return }
            guard let stream = try? await self.groupService.groupChanges(userID: user.id) else { return }
            for await _ in stream {
                guard !Task.isCancelled else { return }
                await self.loadAll()
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
            try await expenseService.createExpense(
                groupID: group.id, title: title, amount: amount,
                currency: "USD", payerID: userID, category: category,
                notes: "Sample expense — feel free to delete", splits: [split]
            )
        }
        groups.append(group)
        CacheService.shared.saveGroups(groups)
    }

    // MARK: - Balance + Recent Expenses

    private func computeBalances(for userID: UUID) async {
        guard !isComputingBalances else { return }
        isComputingBalances = true
        defer { isComputingBalances = false }
        // Invalidate balance cache at the start of each full recompute.
        groupBalancesCache.removeAll()
        var owed             = Decimal.zero
        var owing            = Decimal.zero
        var allEntries:      [RecentEntry]             = []
        var mergedByCurrency:[String: [UUID: Decimal]] = [:]
        var allNames:        [UUID: String]            = [:]

        await withTaskGroup(of: GroupBalanceData.self) { taskGroup in
            for group in groups {
                taskGroup.addTask {
                    await self.fullBalancesInGroup(group, userID: userID)
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
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func fullBalancesInGroup(_ group: BillGroup, userID: UUID) async -> GroupBalanceData {
        // Return cached result if already computed this cycle (avoids redundant network calls).
        if let cached = groupBalancesCache[group.id] { return cached }

        guard let expenses = try? await expenseService.fetchExpenses(groupID: group.id) else {
            let empty = GroupBalanceData(groupID: group.id, owed: .zero, owing: .zero, netBalance: .zero,
                                         memberCount: 0, entries: [],
                                         currency: group.currency, balances: [:], names: [:])
            groupBalancesCache[group.id] = empty
            return empty
        }
        let members   = (try? await groupService.fetchMembers(groupID: group.id)) ?? []
        let splitsMap = await SplitCalculator.fetchSplitsMap(for: expenses, using: expenseService)
        let balances  = SplitCalculator.netBalances(expenses: expenses, splits: splitsMap)
        let net       = balances[userID] ?? .zero
        let owed      = net > .zero ? net  : .zero
        let owing     = net < .zero ? -net : .zero
        let entries   = expenses.map { RecentEntry(expense: $0, members: members) }
        let names     = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })
        let data      = GroupBalanceData(groupID: group.id, owed: owed, owing: owing, netBalance: net,
                                         memberCount: members.count, entries: entries,
                                         currency: group.currency, balances: balances, names: names)
        groupBalancesCache[group.id] = data
        return data
    }
}

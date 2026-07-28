//
//  ActivityService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

@MainActor
final class ActivityService {
    static let shared = ActivityService()
    private let groupService   = GroupService.shared
    private let expenseService = ExpenseService.shared
    private let store          = NotificationStore.shared
    private let remote         = RemoteNotificationService.shared

    private init() {}

    /// Fetches server notifications and supplements them with historical expense
    /// activity. Historical rows are read-only context; only server notification
    /// rows participate in unread state and badge counts.
    func fetchRecentActivity(userID: UUID, limit: Int = 50) async throws -> [NotificationItem] {
        var remoteItems: [NotificationItem] = []
        do {
            remoteItems = try await remote.fetch(userID: userID)
        } catch {
            AppDiagnostics.log(.balance, "ActivityService.remoteFetch.fallback", [
                ("error", AppDiagnostics.describe(error))
            ])
            // Preserve the previous error/partial-result behavior when the
            // server-backed table is unavailable.
            let legacyItems = try await fetchLegacyExpenseActivity(userID: userID)
            store.merge(legacyItems, userID: userID)
            return Array(store.loadAll(userID: userID).prefix(limit))
        }

        // Existing accounts predate migration 040, so their historical
        // expenses have no notification rows. Keep those visible without
        // making them unread or inflating the APNs badge.
        let legacyItems = (try? await fetchLegacyExpenseActivity(userID: userID)) ?? []
        let remoteIDs = Set(remoteItems.map(\.id))
        let historicalItems = legacyItems.compactMap { item -> NotificationItem? in
            guard !remoteIDs.contains(item.id) else { return nil }
            var item = item
            item.isRead = true
            return item
        }
        let reconciledItems = store.applyingPendingReadStates(to: remoteItems + historicalItems, userID: userID)
        store.replaceWithRemote(reconciledItems, userID: userID)
        return Array(store.loadAll(userID: userID).prefix(limit))
    }

    func reconcilePendingReadStates(userID: UUID) async {
        for (id, isRead) in store.pendingReadStates(userID: userID) {
            do {
                if isRead {
                    try await remote.markRead(id: id)
                } else {
                    try await remote.markUnread(id: id)
                }
                store.clearPendingReadState(id: id, userID: userID)
            } catch {
                AppDiagnostics.log(.balance, "ActivityService.pendingReadState.retryFailed", [
                    ("error", AppDiagnostics.describe(error))
                ])
            }
        }
    }

    private func fetchLegacyExpenseActivity(userID: UUID) async throws -> [NotificationItem] {
        let groups = try await groupService.fetchGroups(for: userID)

        var fetched: [NotificationItem] = []
        var groupErrors: [Error] = []
        await withTaskGroup(of: Result<[NotificationItem], Error>.self) { taskGroup in
            for group in groups {
                taskGroup.addTask { await self.items(for: group) }
            }
            for await result in taskGroup {
                switch result {
                case .success(let items): fetched.append(contentsOf: items)
                case .failure(let err):   groupErrors.append(err)
                }
            }
        }
        // Throw if any groups failed, so the caller can surface a warning.
        if let first = groupErrors.first { throw first }

        return fetched
    }

    func markRead(id: UUID) async -> Bool {
        do { try await remote.markRead(id: id); return true }
        catch { AppDiagnostics.log(.balance, "ActivityService.markRead.failed", [("error", AppDiagnostics.describe(error))]); return false }
    }

    func markAllRead(userID: UUID) async -> Bool {
        do { try await remote.markAllRead(userID: userID); return true }
        catch { AppDiagnostics.log(.balance, "ActivityService.markAllRead.failed", [("error", AppDiagnostics.describe(error))]); return false }
    }

    func markUnread(id: UUID) async -> Bool {
        do { try await remote.markUnread(id: id); return true }
        catch { AppDiagnostics.log(.balance, "ActivityService.markUnread.failed", [("error", AppDiagnostics.describe(error))]); return false }
    }

    func delete(id: UUID) async -> Bool {
        do { try await remote.delete(id: id); return true }
        catch { AppDiagnostics.log(.balance, "ActivityService.delete.failed", [("error", AppDiagnostics.describe(error))]); return false }
    }

    private func items(for group: BillGroup) async -> Result<[NotificationItem], Error> {
        do {
            async let expensesTask = expenseService.fetchExpenses(groupID: group.id, limit: 50)
            async let membersTask  = groupService.fetchMembers(groupID: group.id, includeInactive: true)
            let expenses = try await expensesTask
            let members  = try await membersTask
            let nameMap  = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })
            let items = expenses.map { expense in
                NotificationItem.expense(
                    expense,
                    payerName: expense.payerID.flatMap { nameMap[$0] } ?? "Someone",
                    groupName: group.name,
                    groupEmoji: group.emoji
                )
            }
            return .success(items)
        } catch {
            return .failure(error)
        }
    }
}

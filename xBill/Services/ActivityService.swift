//
//  ActivityService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

// MARK: - Reconciliation

/// Builds the Activity list from the authoritative `public.notifications` rows plus the
/// historical expense-derived rows shown to accounts that predate migration 040.
///
/// Historical rows have no server row to hold their read state, so it lives only in the
/// local store. The previous implementation forced `isRead = true` on every historical row
/// on every refresh, which erased a deliberate "mark unread" as soon as anything triggered
/// a reload — including the refresh that runs after a Face ID unlock.
enum ActivityReconciler {
    static func reconcile(
        remoteItems: [NotificationItem],
        legacyItems: [NotificationItem],
        storedItems: [NotificationItem],
        pendingReadStates: [UUID: Bool],
        dismissedHistoryIDs: Set<UUID> = []
    ) -> [NotificationItem] {
        let remoteIDs = Set(remoteItems.map(\.id))
        let storedReadStates = Dictionary(
            storedItems.map { ($0.id, $0.isRead) },
            uniquingKeysWith: { _, new in new }
        )

        let historicalItems = legacyItems.compactMap { item -> NotificationItem? in
            // A server row is authoritative whenever one exists for the same id.
            guard !remoteIDs.contains(item.id) else { return nil }
            // A history row the user deleted would otherwise be re-derived from the
            // expense list on every fetch. Never applied to server rows: deletion there is
            // authoritative and the fetch simply stops returning them.
            guard !dismissedHistoryIDs.contains(item.id) else { return nil }
            var item = item
            // Default an unseen history row to read so years of pre-040 expenses do not
            // land in the badge; anything already in the store keeps the state the user
            // last chose.
            item.isRead = storedReadStates[item.id] ?? true
            return item
        }

        return (remoteItems + historicalItems).map { item in
            guard let pending = pendingReadStates[item.id] else { return item }
            var item = item
            item.isRead = pending
            return item
        }
    }
}

// MARK: - Read/write surface

/// The Activity mutations the view model depends on. A protocol so read-state behaviour can
/// be exercised without a live PostgREST endpoint.
@MainActor
protocol ActivityReadWriting: AnyObject {
    func fetchRecentActivity(userID: UUID, limit: Int) async throws -> [NotificationItem]
    func reconcilePendingReadStates(userID: UUID) async
    func markRead(id: UUID) async -> Bool
    func markUnread(id: UUID) async -> Bool
    func markAllRead(userID: UUID) async -> Bool
    func delete(id: UUID) async -> Bool
}

@MainActor
final class ActivityService: ActivityReadWriting {
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
        // inflating the APNs badge, while preserving any read state the user
        // has deliberately chosen for them.
        let legacyItems = (try? await fetchLegacyExpenseActivity(userID: userID)) ?? []
        let reconciledItems = ActivityReconciler.reconcile(
            remoteItems:         remoteItems,
            legacyItems:         legacyItems,
            storedItems:         store.loadAll(userID: userID),
            pendingReadStates:   store.pendingReadStates(userID: userID),
            dismissedHistoryIDs: store.dismissedHistoryIDs(userID: userID)
        )
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
            } catch RemoteNotificationError.rowNotFound(let missingID) {
                // No server row will ever accept this write — retrying it forever would
                // keep the intent pinned and re-raise the same failure on every refresh.
                AppDiagnostics.log(.balance, "ActivityService.pendingReadState.rowNotFound", [
                    ("id", missingID.uuidString)
                ])
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
        catch {
            AppDiagnostics.log(.balance, "ActivityService.markRead.failed", [
                ("id", id.uuidString),
                ("error", AppDiagnostics.describe(error))
            ])
            return false
        }
    }

    func markAllRead(userID: UUID) async -> Bool {
        do { try await remote.markAllRead(userID: userID); return true }
        catch { AppDiagnostics.log(.balance, "ActivityService.markAllRead.failed", [("error", AppDiagnostics.describe(error))]); return false }
    }

    func markUnread(id: UUID) async -> Bool {
        do { try await remote.markUnread(id: id); return true }
        catch {
            AppDiagnostics.log(.balance, "ActivityService.markUnread.failed", [
                ("id", id.uuidString),
                ("error", AppDiagnostics.describe(error))
            ])
            return false
        }
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

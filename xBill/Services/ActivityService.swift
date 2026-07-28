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

    /// Fetches fresh expense activity from the DB, merges into the local store,
    /// then returns the combined list sorted newest-first.
    /// Items already in the store keep their existing read state.
    func fetchRecentActivity(userID: UUID, limit: Int = 50) async throws -> [NotificationItem] {
        do {
            let remoteItems = try await remote.fetch(userID: userID)
            store.replaceWithRemote(remoteItems)
            return Array(store.loadAll().prefix(limit))
        } catch {
            // Keep the expense fallback available until migration 040 is deployed.
            AppDiagnostics.log(.balance, "ActivityService.remoteFetch.fallback", [
                ("error", AppDiagnostics.describe(error))
            ])
        }

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
        // Always merge partial results into the store so the caller can read them
        // from the store even if we throw below.
        store.merge(fetched)
        let allItems = store.loadAll().prefix(limit).map { $0 }

        // Throw if any groups failed, so the caller can surface a warning.
        // On partial failure, items already merged above remain readable from store.
        if let first = groupErrors.first { throw first }

        return allItems
    }

    func markRead(id: UUID) async {
        do { try await remote.markRead(id: id) }
        catch { AppDiagnostics.log(.balance, "ActivityService.markRead.failed", [("error", AppDiagnostics.describe(error))]) }
    }

    func markAllRead(userID: UUID) async {
        do { try await remote.markAllRead(userID: userID) }
        catch { AppDiagnostics.log(.balance, "ActivityService.markAllRead.failed", [("error", AppDiagnostics.describe(error))]) }
    }

    func markUnread(id: UUID) async {
        do { try await remote.markUnread(id: id) }
        catch { AppDiagnostics.log(.balance, "ActivityService.markUnread.failed", [("error", AppDiagnostics.describe(error))]) }
    }

    func delete(id: UUID) async {
        do { try await remote.delete(id: id) }
        catch { AppDiagnostics.log(.balance, "ActivityService.delete.failed", [("error", AppDiagnostics.describe(error))]) }
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

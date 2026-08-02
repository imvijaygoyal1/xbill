//
//  ActivityServiceTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  `ActivityService` sat at 27.7% coverage because it held four hard-coded `.shared`
//  dependencies — `fetchRecentActivity`, `reconcilePendingReadStates`,
//  `fetchLegacyExpenseActivity` and `items(for:)` were all completely unreachable from tests.
//  These exercise the seam added for exactly that.
//

import Testing
import Foundation
@testable import xBill

@Suite("ActivityService")
@MainActor
struct ActivityServiceTests {

    // MARK: - Fakes

    @MainActor final class FakeRemote: RemoteNotificationProviding {
        var items: [NotificationItem] = []
        var fetchError: Error?
        var readCalls: [UUID] = []
        var unreadCalls: [UUID] = []
        var failingIDs: Set<UUID> = []
        /// Ids the server no longer has — the state that must clear a pending intent rather than
        /// retry a write that can never succeed.
        var missingIDs: Set<UUID> = []

        func fetch(userID: UUID, limit: Int) async throws -> [NotificationItem] {
            if let fetchError { throw fetchError }
            return items
        }
        func markRead(id: UUID) async throws {
            readCalls.append(id)
            if missingIDs.contains(id) { throw SupabaseWriteError.noRowsAffected(table: "notifications", id: id) }
            if failingIDs.contains(id) { throw AppError.networkUnavailable }
        }
        func markUnread(id: UUID) async throws {
            unreadCalls.append(id)
            if missingIDs.contains(id) { throw SupabaseWriteError.noRowsAffected(table: "notifications", id: id) }
            if failingIDs.contains(id) { throw AppError.networkUnavailable }
        }
        func markAllRead(userID: UUID) async throws {}
        func delete(id: UUID) async throws {}
    }

    @MainActor final class StubGroups: GroupDataProviding {
        var groups: [BillGroup] = []
        var members: [User] = []
        func fetchGroups(for userID: UUID) async throws -> [BillGroup] { groups }
        func fetchMembers(groupID: UUID, includeInactive: Bool) async throws -> [User] { members }
        func addMember(groupId: UUID, userId: UUID) async throws {}
        func removeMember(groupId: UUID, userId: UUID) async throws {}
        func updateGroup(_ group: BillGroup) async throws -> BillGroup { group }
    }

    private func makeStore() -> NotificationStore {
        let suffix = UUID().uuidString
        return NotificationStore(itemsKey: "as_items_\(suffix)",
                                 lastViewedKey: "as_viewed_\(suffix)",
                                 pendingReadKey: "as_pending_\(suffix)")
    }

    private func makeService(remote: FakeRemote,
                             store: NotificationStore,
                             groups: StubGroups = StubGroups(),
                             expenses: FakeExpenseService = FakeExpenseService()) -> ActivityService {
        ActivityService(groupService: groups, expenseService: expenses, store: store, remote: remote)
    }

    private func serverItem(isRead: Bool = false) -> NotificationItem {
        .remote(id: UUID(), eventType: .expenseAdded, title: "Groceries", subtitle: "🏠 Roommates",
                amount: 18, currency: "USD", category: .food, createdAt: Date(),
                isRead: isRead, groupID: nil, expenseID: nil)
    }

    // MARK: - fetchRecentActivity

    @Test("Server rows are persisted and returned, capped at the limit")
    func fetchPersistsAndCaps() async throws {
        let user = UUID(); let remote = FakeRemote(); let store = makeStore()
        remote.items = (0..<5).map { _ in serverItem() }

        let result = try await makeService(remote: remote, store: store)
            .fetchRecentActivity(userID: user, limit: 3)

        #expect(result.count == 3, "The caller's limit must be honoured.")
        #expect(store.loadAll(userID: user).count == 5, "All fetched rows are cached, not just the page shown.")
    }

    // MARK: - reconcilePendingReadStates

    /// A pending intent exists because a read/unread write failed while offline. It must be
    /// replayed and then cleared, or the same write is reissued forever.
    @Test("A pending read intent is replayed and cleared")
    func pendingIntentIsReplayedAndCleared() async {
        let user = UUID(); let remote = FakeRemote(); let store = makeStore()
        let item = serverItem()
        store.merge([item], userID: user)
        store.setPendingReadState(id: item.id, isRead: true, userID: user)

        await makeService(remote: remote, store: store).reconcilePendingReadStates(userID: user)

        #expect(remote.readCalls == [item.id], "The intent must actually reach the server.")
        #expect(store.pendingReadStates(userID: user).isEmpty, "A replayed intent must not persist.")
    }

    /// NOTIF-12: a row the server no longer has can never accept the write. Retrying it forever
    /// was the defect; the intent must be dropped.
    @Test("An intent for a row the server no longer has is dropped, not retried")
    func missingRowClearsIntent() async {
        let user = UUID(); let remote = FakeRemote(); let store = makeStore()
        let item = serverItem()
        store.merge([item], userID: user)
        store.setPendingReadState(id: item.id, isRead: true, userID: user)
        remote.missingIDs = [item.id]

        await makeService(remote: remote, store: store).reconcilePendingReadStates(userID: user)

        #expect(store.pendingReadStates(userID: user).isEmpty,
                "A write that can never succeed must not be retried on every refresh.")
    }

    /// A transient failure is the opposite case: the intent must survive to be retried.
    @Test("A transient failure keeps the intent for a later retry")
    func transientFailureKeepsIntent() async {
        let user = UUID(); let remote = FakeRemote(); let store = makeStore()
        let item = serverItem()
        store.merge([item], userID: user)
        store.setPendingReadState(id: item.id, isRead: false, userID: user)
        remote.failingIDs = [item.id]

        await makeService(remote: remote, store: store).reconcilePendingReadStates(userID: user)

        #expect(!store.pendingReadStates(userID: user).isEmpty,
                "A network failure must not discard the user's intent.")
        #expect(remote.unreadCalls == [item.id])
    }
}

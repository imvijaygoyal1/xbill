//
//  NotificationReadStateTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Regression cover for the "marking a notification unread does not survive an app-lock
//  cycle" defect found on a physical iPhone on 2026-07-28.
//
//  Two faults compounded:
//
//  1. The Activity list mixes authoritative `public.notifications` rows with historical
//     expense-derived rows whose `id` is an *expense* id. Those ids do not exist in the
//     notifications table (verified against the live database: 12 expenses, 3 notification
//     rows, zero id overlap), so every read/unread PATCH for one matched zero rows, and
//     `fetchRecentActivity` then forced `isRead = true` on the historical row on the next
//     refresh — which is what erased the user's unread mark after Face ID unlock.
//
//  2. `.single()` was used to acknowledge the write. It only sets an Accept header; on a
//     zero-row match PostgREST answers PGRST116 "Cannot coerce the result to a single JSON
//     object", which reads as a response-shape problem and hides "no row matched".
//     `return=representation` sends an ARRAY, so the affected-row count is what must be
//     checked.
//

import Foundation
import Testing
@testable import xBill

// MARK: - Wire payload

@Suite("Notification read-state PATCH payload")
struct NotificationReadStatePayloadTests {

    /// The client sends this through the Postgrest configuration encoder, not a bare
    /// `JSONEncoder`, so the tests must encode the same way the request does.
    private func encoded(_ payload: NotificationReadStatePayload) throws -> [String: Any] {
        let data = try SupabaseManager.postgrestEncoder.encode(payload)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("An unread transition sends an explicit JSON null, not an omitted key")
    func unreadEncodesExplicitNull() throws {
        let json = try encoded(NotificationReadStatePayload(readAt: nil))

        // Swift's synthesized Encodable omits nil optionals. A PATCH without the key is a
        // no-op that can never clear read_at, so the row stays read on the server.
        #expect(json.keys.contains("read_at"))
        #expect(json["read_at"] is NSNull)
    }

    /// The SDK's own date strategy emits a zone-less `2023-11-14T22:13:20.000`, which lands
    /// correctly only because this project's Postgres session `TimeZone` happens to be UTC.
    /// The read time is pinned to an explicit UTC instant so it does not depend on that.
    @Test("A read transition sends read_at as an explicit UTC ISO-8601 instant")
    func readEncodesUTCInstant() throws {
        let json = try encoded(NotificationReadStatePayload(readAt: Date(timeIntervalSince1970: 1_700_000_000)))

        // A bare `Date` through a plain JSONEncoder would be a number here, which Postgres
        // cannot cast to timestamptz at all.
        #expect(json["read_at"] as? String == "2023-11-14T22:13:20Z")
    }
}

// MARK: - Affected-row acknowledgement

@Suite("Notification read-state update acknowledgement")
struct NotificationReadStateAcknowledgementTests {

    @Test("A zero-row update is reported as a missing row, not a JSON coercion failure")
    func zeroRowsThrowsRowNotFound() {
        let id = UUID()
        #expect(throws: RemoteNotificationError.rowNotFound(id)) {
            try RemoteNotificationService.acknowledgeAffectedRows([], id: id)
        }
    }

    @Test("A single affected row is accepted")
    func oneRowSucceeds() throws {
        let id = UUID()
        try RemoteNotificationService.acknowledgeAffectedRows([NotificationRowID(id: id)], id: id)
    }

    /// Pins the response shape. `update(...).select("id")` sends `Prefer: return=representation`,
    /// and PostgREST answers with a JSON *array* of the updated rows. Decoding it as an array
    /// is what makes the affected-row count observable; `.single()` only swaps the Accept
    /// header and turns a zero-row match into an opaque coercion error.
    @Test("The update response decodes as an array of rows")
    func responseDecodesAsArray() throws {
        let id = UUID()
        let body = Data(#"[{"id":"\#(id.uuidString)"}]"#.utf8)

        let rows = try JSONDecoder().decode([NotificationRowID].self, from: body)

        #expect(rows.count == 1)
        try RemoteNotificationService.acknowledgeAffectedRows(rows, id: id)
    }

    @Test("An empty array response is the wire shape of a zero-row match")
    func emptyArrayIsZeroRows() throws {
        let id = UUID()
        let rows = try JSONDecoder().decode([NotificationRowID].self, from: Data("[]".utf8))

        #expect(rows.isEmpty)
        #expect(throws: RemoteNotificationError.rowNotFound(id)) {
            try RemoteNotificationService.acknowledgeAffectedRows(rows, id: id)
        }
    }
}

// MARK: - Activity list reconciliation

@Suite("Activity list reconciliation")
struct ActivityReconcilerTests {

    private func expenseItem(id: UUID = UUID(), title: String = "Dinner") -> NotificationItem {
        NotificationItem.expense(
            Expense(
                id:                 id,
                groupID:            UUID(),
                title:              title,
                amount:             42,
                currency:           "USD",
                payerID:            UUID(),
                category:           .food,
                notes:              nil,
                receiptURL:         nil,
                originalAmount:     nil,
                originalCurrency:   nil,
                recurrence:         .none,
                nextOccurrenceDate: nil,
                createdAt:          Date(timeIntervalSince1970: 1_700_000_000)
            ),
            payerName:  "Alice",
            groupName:  "Roommates",
            groupEmoji: "🏠"
        )
    }

    private func remoteItem(id: UUID = UUID(), isRead: Bool) -> NotificationItem {
        .remote(
            id:        id,
            eventType: .expenseAdded,
            title:     "Groceries",
            subtitle:  "🏠 Roommates · Paid by Bob",
            amount:    18,
            currency:  "USD",
            category:  .food,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            isRead:    isRead,
            groupID:   nil,
            expenseID: nil
        )
    }

    /// The reported defect. The user marks a historical row unread; the app is locked and
    /// unlocked, which triggers a refresh. Before the fix the refresh forced `isRead = true`
    /// on every historical row unconditionally, so the unread mark was erased.
    @Test("A historical item the user marked unread stays unread across a refresh")
    func historicalUnreadSurvivesRefresh() {
        let legacy = expenseItem()
        var stored = legacy
        stored.isRead = false

        let result = ActivityReconciler.reconcile(
            remoteItems:       [],
            legacyItems:       [legacy],
            storedItems:       [stored],
            pendingReadStates: [:]
        )

        let reconciled = try? #require(result.first { $0.id == legacy.id })
        #expect(reconciled?.isRead == false)
    }

    /// The reason the previous code forced `isRead = true`: accounts that predate migration
    /// 040 have years of expense history with no notification rows, and treating all of it
    /// as unread would inflate the badge. Defaulting only *unseen* rows to read keeps that
    /// property while leaving deliberate user marks alone.
    @Test("A historical item that has never been stored defaults to read")
    func unseenHistoricalItemDefaultsToRead() {
        let legacy = expenseItem()

        let result = ActivityReconciler.reconcile(
            remoteItems:       [],
            legacyItems:       [legacy],
            storedItems:       [],
            pendingReadStates: [:]
        )

        #expect(result.first?.isRead == true)
    }

    @Test("A historical item previously seen as read stays read")
    func seenHistoricalReadItemStaysRead() {
        let legacy = expenseItem()
        var stored = legacy
        stored.isRead = true

        let result = ActivityReconciler.reconcile(
            remoteItems:       [],
            legacyItems:       [legacy],
            storedItems:       [stored],
            pendingReadStates: [:]
        )

        #expect(result.first?.isRead == true)
    }

    @Test("Server read state is authoritative for server-backed rows")
    func serverStateWinsForRemoteRows() {
        let remote = remoteItem(isRead: true)
        var stored = remote
        stored.isRead = false

        let result = ActivityReconciler.reconcile(
            remoteItems:       [remote],
            legacyItems:       [],
            storedItems:       [stored],
            pendingReadStates: [:]
        )

        #expect(result.first?.isRead == true)
    }

    @Test("A pending local intent overrides a stale server response")
    func pendingIntentOverridesServerState() {
        let remote = remoteItem(isRead: true)

        let result = ActivityReconciler.reconcile(
            remoteItems:       [remote],
            legacyItems:       [],
            storedItems:       [],
            pendingReadStates: [remote.id: false]
        )

        #expect(result.first?.isRead == false)
    }

    /// A history row has no server row to delete, so dismissing one is recorded locally.
    /// Without that record the next fetch re-derives it straight from the expense list and
    /// the row the user deleted comes back.
    @Test("A dismissed history item is not re-derived on the next refresh")
    func dismissedHistoryItemStaysDeleted() {
        let legacy = expenseItem()

        let result = ActivityReconciler.reconcile(
            remoteItems:       [],
            legacyItems:       [legacy],
            storedItems:       [],
            pendingReadStates: [:],
            dismissedHistoryIDs: [legacy.id]
        )

        #expect(result.isEmpty)
    }

    /// Deletion of a server row is authoritative on the server — the fetch simply stops
    /// returning it. A local dismissal record must never suppress a live server row.
    @Test("A dismissal record does not suppress a server-backed row")
    func dismissalDoesNotHideServerRow() {
        let remote = remoteItem(isRead: false)

        let result = ActivityReconciler.reconcile(
            remoteItems:       [remote],
            legacyItems:       [],
            storedItems:       [],
            pendingReadStates: [:],
            dismissedHistoryIDs: [remote.id]
        )

        #expect(result.count == 1)
        #expect(result.first?.id == remote.id)
    }

    @Test("A legacy item duplicating a server row is dropped in favour of the server row")
    func serverRowSupersedesLegacyDuplicate() {
        let sharedID = UUID()
        let remote = remoteItem(id: sharedID, isRead: false)
        let legacy = expenseItem(id: sharedID)

        let result = ActivityReconciler.reconcile(
            remoteItems:       [remote],
            legacyItems:       [legacy],
            storedItems:       [],
            pendingReadStates: [:]
        )

        #expect(result.count == 1)
        #expect(result.first?.isServerBacked == true)
        #expect(result.first?.isRead == false)
    }
}

// MARK: - Item origin

@Suite("NotificationItem origin")
struct NotificationItemOriginTests {

    @Test("A server notification row is server-backed")
    func remoteItemIsServerBacked() {
        let item = NotificationItem.remote(
            id: UUID(), eventType: .expenseAdded, title: "T", subtitle: "S",
            amount: 1, currency: "USD", category: .other,
            createdAt: Date(), isRead: false, groupID: nil, expenseID: nil
        )
        #expect(item.isServerBacked)
    }

    /// Expense-derived rows carry an expense id. Routing a read/unread PATCH for one at the
    /// notifications table is what produced the zero-row update on device.
    @Test("An expense-derived history row is not server-backed")
    func expenseItemIsNotServerBacked() {
        let item = NotificationItem.expense(
            Expense(
                id: UUID(), groupID: UUID(), title: "Dinner", amount: 42, currency: "USD",
                payerID: UUID(), category: .food, notes: nil, receiptURL: nil,
                originalAmount: nil, originalCurrency: nil, recurrence: .none,
                nextOccurrenceDate: nil, createdAt: Date()
            ),
            payerName: "Alice", groupName: "Roommates", groupEmoji: "🏠"
        )
        #expect(!item.isServerBacked)
    }

    @Test("A cache entry written before the origin flag existed decodes as not server-backed")
    func legacyCacheEntryDecodesAsLocal() throws {
        // Exactly the shape already sitting in App Group UserDefaults on the test device.
        let json = """
        {"id":"\(UUID().uuidString)","eventType":"expenseAdded","title":"Dinner",
         "subtitle":"🏠 Roommates · Paid by Alice","amount":42,"currency":"USD",
         "category":"food","createdAt":1700000000,"isRead":true}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let item = try decoder.decode(NotificationItem.self, from: Data(json.utf8))

        #expect(!item.isServerBacked)
        #expect(item.isRead)
    }

    @Test("The origin flag survives a cache round-trip")
    func originSurvivesRoundTrip() throws {
        let original = NotificationItem.remote(
            id: UUID(), eventType: .settlementMade, title: "T", subtitle: "S",
            amount: 5, currency: "USD", category: .other,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            isRead: false, groupID: nil, expenseID: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let decoded = try decoder.decode(NotificationItem.self, from: try encoder.encode(original))

        #expect(decoded.isServerBacked)
    }
}

// MARK: - Dismissed history rows

@Suite("NotificationStore — dismissed history rows")
struct NotificationStoreDismissalTests {

    private func makeStore() -> NotificationStore {
        let suffix = UUID().uuidString
        return NotificationStore(
            itemsKey:       "test_items_\(suffix)",
            lastViewedKey:  "test_viewed_\(suffix)",
            pendingReadKey: "test_pending_\(suffix)",
            dismissedKey:   "test_dismissed_\(suffix)"
        )
    }

    @Test("A dismissal is persisted")
    func dismissalPersists() {
        let store = makeStore()
        let user  = UUID()
        let id    = UUID()

        store.dismissHistoryItem(id: id, userID: user)

        #expect(store.dismissedHistoryIDs(userID: user).contains(id))
    }

    @Test("Dismissals are scoped per account")
    func dismissalsAreUserScoped() {
        let store = makeStore()
        let userA = UUID()
        let userB = UUID()
        let id    = UUID()

        store.dismissHistoryItem(id: id, userID: userA)

        #expect(store.dismissedHistoryIDs(userID: userB).isEmpty)
    }

    /// The record is append-only, so it needs a bound — otherwise it grows for the life of
    /// the install.
    @Test("Dismissals are capped, keeping the most recent")
    func dismissalsAreCapped() {
        let store = makeStore()
        let user  = UUID()
        let ids   = (0..<250).map { _ in UUID() }

        for id in ids { store.dismissHistoryItem(id: id, userID: user) }

        let stored = store.dismissedHistoryIDs(userID: user)
        #expect(stored.count == 200)
        #expect(stored.contains(ids.last!))
        #expect(!stored.contains(ids.first!))
    }
}

// MARK: - View model read mutations

@Suite("ActivityViewModel read mutations", .serialized)
@MainActor
struct ActivityViewModelReadMutationTests {

    /// Records what the view model actually asked the server to do.
    final class FakeActivityService: ActivityReadWriting {
        enum Call: Equatable { case markRead(UUID), markUnread(UUID), markAllRead, delete(UUID) }

        var calls: [Call] = []
        var result = true

        func fetchRecentActivity(userID: UUID, limit: Int) async throws -> [NotificationItem] { [] }
        func reconcilePendingReadStates(userID: UUID) async {}
        func markRead(id: UUID) async -> Bool { calls.append(.markRead(id)); return result }
        func markUnread(id: UUID) async -> Bool { calls.append(.markUnread(id)); return result }
        func markAllRead(userID: UUID) async -> Bool { calls.append(.markAllRead); return result }
        func delete(id: UUID) async -> Bool { calls.append(.delete(id)); return result }
    }

    private func makeStore() -> NotificationStore {
        let suffix = UUID().uuidString
        return NotificationStore(
            itemsKey:       "test_items_\(suffix)",
            lastViewedKey:  "test_viewed_\(suffix)",
            pendingReadKey: "test_pending_\(suffix)"
        )
    }

    private func serverItem(isRead: Bool) -> NotificationItem {
        .remote(
            id: UUID(), eventType: .expenseAdded, title: "Groceries", subtitle: "🏠 Roommates",
            amount: 18, currency: "USD", category: .food, createdAt: Date(),
            isRead: isRead, groupID: nil, expenseID: nil
        )
    }

    private func historyItem() -> NotificationItem {
        NotificationItem.expense(
            Expense(
                id: UUID(), groupID: UUID(), title: "Dinner", amount: 42, currency: "USD",
                payerID: UUID(), category: .food, notes: nil, receiptURL: nil,
                originalAmount: nil, originalCurrency: nil, recurrence: .none,
                nextOccurrenceDate: nil, createdAt: Date()
            ),
            payerName: "Alice", groupName: "Roommates", groupEmoji: "🏠"
        )
    }

    /// Polls on the main actor so queued `Task { @MainActor in … }` mutation work can run.
    private func settle(_ vm: ActivityViewModel) async {
        for _ in 0..<200 {
            if !vm.hasInFlightMutations { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    @Test("Marking a history row unread performs no server write and keeps it unread")
    func historyRowUnreadIsLocalOnly() async {
        let fake  = FakeActivityService()
        let store = makeStore()
        let user  = UUID()
        var item  = historyItem()
        item.isRead = true
        store.replaceWithRemote([item], userID: user)

        let vm = ActivityViewModel(service: fake, store: store, currentUserIDProvider: { user })
        vm.items = [item]

        vm.markUnread(item)
        await settle(vm)

        // A PATCH against public.notifications with an expense id matches zero rows.
        #expect(fake.calls.isEmpty)
        #expect(vm.items.first?.isRead == false)
        #expect(store.loadAll(userID: user).first?.isRead == false)
        // No pending intent either — there is nothing for the retry loop to replay.
        #expect(store.pendingReadStates(userID: user).isEmpty)
        #expect(vm.errorAlert == nil)
    }

    @Test("Marking a server-backed row unread writes through to the server")
    func serverRowUnreadIsWrittenThrough() async {
        let fake  = FakeActivityService()
        let store = makeStore()
        let user  = UUID()
        let item  = serverItem(isRead: true)
        store.replaceWithRemote([item], userID: user)

        let vm = ActivityViewModel(service: fake, store: store, currentUserIDProvider: { user })
        vm.items = [item]

        vm.markUnread(item)
        await settle(vm)

        #expect(fake.calls == [.markUnread(item.id)])
        #expect(vm.items.first?.isRead == false)
        #expect(store.pendingReadStates(userID: user).isEmpty)
    }

    @Test("A failed server write rolls the item back and reports it")
    func failedWriteRollsBack() async {
        let fake  = FakeActivityService()
        fake.result = false
        let store = makeStore()
        let user  = UUID()
        let item  = serverItem(isRead: true)
        store.replaceWithRemote([item], userID: user)

        let vm = ActivityViewModel(service: fake, store: store, currentUserIDProvider: { user })
        vm.items = [item]

        vm.markUnread(item)
        await settle(vm)

        #expect(vm.items.first?.isRead == true)
        #expect(store.loadAll(userID: user).first?.isRead == true)
        #expect(vm.errorAlert != nil)
    }

    /// A rollback must not resurrect unrelated rows from the snapshot it was holding.
    @Test("A rollback only touches the item that failed")
    func rollbackIsScopedToOneItem() async {
        let fake  = FakeActivityService()
        fake.result = false
        let store = makeStore()
        let user  = UUID()
        let failing  = serverItem(isRead: true)
        let untouched = serverItem(isRead: false)
        store.replaceWithRemote([failing, untouched], userID: user)

        let vm = ActivityViewModel(service: fake, store: store, currentUserIDProvider: { user })
        vm.items = [failing, untouched]

        vm.markUnread(failing)
        await settle(vm)

        #expect(vm.items.first { $0.id == failing.id }?.isRead == true)
        #expect(vm.items.first { $0.id == untouched.id }?.isRead == false)
        #expect(store.loadAll(userID: user).count == 2)
    }

    @Test("Deleting a history row records a dismissal instead of calling the server")
    func historyRowDeleteIsLocalOnly() async {
        let fake  = FakeActivityService()
        let store = makeStore()
        let user  = UUID()
        let item  = historyItem()
        store.replaceWithRemote([item], userID: user)

        let vm = ActivityViewModel(service: fake, store: store, currentUserIDProvider: { user })
        vm.items = [item]

        vm.delete(item)
        await settle(vm)

        // DELETE ... WHERE id = <expense id> matches zero rows; there is nothing to call.
        #expect(fake.calls.isEmpty)
        #expect(vm.items.isEmpty)
        #expect(store.dismissedHistoryIDs(userID: user).contains(item.id))
        #expect(vm.errorAlert == nil)
    }

    @Test("Deleting a server-backed row calls the server")
    func serverRowDeleteIsWrittenThrough() async {
        let fake  = FakeActivityService()
        let store = makeStore()
        let user  = UUID()
        let item  = serverItem(isRead: false)
        store.replaceWithRemote([item], userID: user)

        let vm = ActivityViewModel(service: fake, store: store, currentUserIDProvider: { user })
        vm.items = [item]

        vm.delete(item)
        await settle(vm)

        #expect(fake.calls == [.delete(item.id)])
        #expect(vm.items.isEmpty)
        // A server row is gone server-side; no local dismissal record is needed.
        #expect(store.dismissedHistoryIDs(userID: user).isEmpty)
    }

    /// The restore must put the row back where it was and leave its neighbours alone.
    @Test("A failed delete restores the row at its original position")
    func failedDeleteRestoresInPlace() async {
        let fake  = FakeActivityService()
        fake.result = false
        let store = makeStore()
        let user  = UUID()
        let first  = serverItem(isRead: true)
        let middle = serverItem(isRead: false)
        let last   = serverItem(isRead: true)
        store.replaceWithRemote([first, middle, last], userID: user)

        let vm = ActivityViewModel(service: fake, store: store, currentUserIDProvider: { user })
        vm.items = [first, middle, last]

        vm.delete(middle)
        await settle(vm)

        #expect(vm.items.map(\.id) == [first.id, middle.id, last.id])
        #expect(vm.items[1].isRead == false)
        #expect(store.loadAll(userID: user).count == 3)
        #expect(vm.errorAlert != nil)
    }

    @Test("The last of several rapid toggles wins")
    func lastRapidToggleWins() async {
        let fake  = FakeActivityService()
        let store = makeStore()
        let user  = UUID()
        let item  = serverItem(isRead: true)
        store.replaceWithRemote([item], userID: user)

        let vm = ActivityViewModel(service: fake, store: store, currentUserIDProvider: { user })
        vm.items = [item]

        vm.markUnread(item)
        vm.markRead(vm.items[0])
        vm.markUnread(vm.items[0])
        await settle(vm)

        #expect(vm.items.first?.isRead == false)
        #expect(store.loadAll(userID: user).first?.isRead == false)
        #expect(fake.calls.last == .markUnread(item.id))
        #expect(store.pendingReadStates(userID: user).isEmpty)
    }
}

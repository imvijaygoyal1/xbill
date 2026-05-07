//
//  P1NotificationTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Testing
import Foundation
@testable import xBill

// MARK: - NotificationStore

@Suite("NotificationStore — Persistence", .serialized)
struct NotificationStoreTests {

    private let store = NotificationStore.shared

    private func makeExpenseItem(
        title: String = "Coffee",
        daysAgo: Double = 0,
        isRead: Bool = false
    ) -> NotificationItem {
        NotificationItem(
            id:        UUID(),
            eventType: .expenseAdded,
            title:     title,
            subtitle:  "🏠 Roommates · Paid by Alice",
            amount:    12.50,
            currency:  "USD",
            category:  .food,
            createdAt: Date().addingTimeInterval(-daysAgo * 86400),
            isRead:    isRead
        )
    }

    @Test("merge adds new items and deduplicates by id")
    func mergeDeduplicates() {
        store.clearAll()
        let item = makeExpenseItem(title: "Lunch")
        store.merge([item])
        store.merge([item]) // same id → should not duplicate
        #expect(store.loadAll().count == 1)
    }

    @Test("merge preserves existing read state for known ids")
    func mergePreservesReadState() {
        store.clearAll()
        let item = makeExpenseItem(title: "Dinner")
        store.merge([item])
        store.markRead(id: item.id)

        var fetchedAgain = item
        fetchedAgain.isRead = false
        store.merge([fetchedAgain])
        #expect(store.loadAll().count == 1)
        #expect(store.loadAll().first?.isRead == true)
    }

    @Test("loadAll returns newest items first")
    func loadAllSortedNewestFirst() {
        store.clearAll()
        let old  = makeExpenseItem(title: "Old", daysAgo: 3)
        let mid  = makeExpenseItem(title: "Mid", daysAgo: 1)
        let new_ = makeExpenseItem(title: "New", daysAgo: 0)
        store.merge([old, mid, new_])
        let loaded = store.loadAll()
        #expect(loaded[0].title == "New")
        #expect(loaded[2].title == "Old")
    }

    @Test("unreadCount is 0 before any items added")
    func unreadCountStartsZero() {
        store.clearAll()
        #expect(store.unreadCount() == 0)
    }

    @Test("unreadCount equals items added after markAllRead baseline")
    func unreadCountAfterNewItems() {
        store.clearAll()
        store.markAllRead()
        let item = NotificationItem(
            id:        UUID(),
            eventType: .expenseAdded,
            title:     "New",
            subtitle:  "",
            amount:    5,
            currency:  "USD",
            category:  .food,
            createdAt: Date()
        )
        store.merge([item])
        #expect(store.unreadCount() == 1)
    }

    @Test("markAllRead resets unread count to zero")
    func markAllReadResetsCount() {
        store.clearAll()
        let item = makeExpenseItem(title: "Tea")
        store.merge([item])
        let beforeMark = store.unreadCount()
        store.markAllRead()
        #expect(beforeMark >= 1)
        #expect(store.unreadCount() == 0)
        #expect(store.loadAll().allSatisfy { $0.isRead })
    }

    @Test("markRead and markUnread update one item")
    func markReadUnreadSingleItem() {
        store.clearAll()
        let first = makeExpenseItem(title: "First")
        let second = makeExpenseItem(title: "Second")
        store.merge([first, second])

        store.markRead(id: first.id)
        #expect(store.loadAll().first(where: { $0.id == first.id })?.isRead == true)
        #expect(store.loadAll().first(where: { $0.id == second.id })?.isRead == false)
        #expect(store.unreadCount() == 1)

        store.markUnread(id: first.id)
        #expect(store.loadAll().first(where: { $0.id == first.id })?.isRead == false)
        #expect(store.unreadCount() == 2)
    }

    @Test("delete removes one notification")
    func deleteRemovesItem() {
        store.clearAll()
        let first = makeExpenseItem(title: "First")
        let second = makeExpenseItem(title: "Second")
        store.merge([first, second])

        store.delete(id: first.id)
        let loaded = store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == second.id)
    }

    @Test("store caps items at 100")
    func storeCapsAt100() {
        store.clearAll()
        let items = (0..<120).map { i in
            NotificationItem(
                id:        UUID(),
                eventType: .expenseAdded,
                title:     "Item \(i)",
                subtitle:  "",
                amount:    1,
                currency:  "USD",
                category:  .other,
                createdAt: Date().addingTimeInterval(Double(i))
            )
        }
        store.merge(items)
        #expect(store.loadAll().count == 100)
    }
}

// MARK: - NotificationItem factory

@Suite("NotificationItem — Factory Methods")
struct NotificationItemFactoryTests {

    @Test("expense factory maps all fields correctly")
    func expenseFactory() {
        let expense = Expense(
            id:           UUID(),
            groupID:      UUID(),
            title:        "Pizza",
            amount:       30.00,
            currency:     "USD",
            payerID:      UUID(),
            category:     .food,
            notes:        nil,
            receiptURL:   nil,
            originalAmount: nil,
            originalCurrency: nil,
            recurrence:   .none,
            nextOccurrenceDate: nil,
            createdAt:    Date()
        )
        let item = NotificationItem.expense(
            expense,
            payerName: "Alice",
            groupName: "Roommates",
            groupEmoji: "🏠"
        )
        #expect(item.id == expense.id)
        #expect(item.eventType == .expenseAdded)
        #expect(item.title == "Pizza")
        #expect(item.subtitle.contains("Alice"))
        #expect(item.subtitle.contains("Roommates"))
        #expect(item.amount == 30.00)
        #expect(item.currency == "USD")
        #expect(item.category == .food)
        #expect(item.groupID == expense.groupID)
        #expect(item.expenseID == expense.id)
        #expect(!item.isRead)
    }

    @Test("settlement factory maps all fields correctly")
    func settlementFactory() {
        let suggestion = SettlementSuggestion(
            id:         UUID(),
            fromUserID: UUID(),
            fromName:   "Bob",
            toUserID:   UUID(),
            toName:     "Alice",
            amount:     25.00,
            currency:   "USD"
        )
        let item = NotificationItem.settlement(
            suggestion: suggestion,
            groupName: "Trip",
            groupEmoji: "✈️"
        )
        #expect(item.id == suggestion.id)
        #expect(item.eventType == .settlementMade)
        #expect(item.title.contains("Bob"))
        #expect(item.subtitle.contains("Alice"))
        #expect(item.amount == 25.00)
        #expect(item.category == .other)
        #expect(!item.isRead)
    }
}

// MARK: - ActivityViewModel unread tracking

@Suite("ActivityViewModel — Unread State")
@MainActor
struct ActivityViewModelUnreadTests {

    @Test("hasUnread is false when unreadCount is zero")
    func hasUnreadFalseWhenZero() {
        let vm = ActivityViewModel()
        vm.unreadCount = 0
        #expect(!vm.hasUnread)
    }

    @Test("hasUnread is true when unreadCount is positive")
    func hasUnreadTrueWhenPositive() {
        let vm = ActivityViewModel()
        vm.unreadCount = 3
        #expect(vm.hasUnread)
    }

    @Test("markAllRead zeros unreadCount on vm")
    func markAllReadZerosVM() {
        NotificationStore.shared.clearAll()
        let vm = ActivityViewModel()
        vm.unreadCount = 5
        vm.markAllRead()
        #expect(vm.unreadCount == 0)
    }

    @Test("markRead and delete update vm items and unread count")
    func markReadAndDeleteUpdateVM() {
        NotificationStore.shared.clearAll()
        let item = NotificationItem(
            id:        UUID(),
            eventType: .expenseAdded,
            title:     "Dinner",
            subtitle:  "Roommates · Paid by Alice",
            amount:    42,
            currency:  "USD",
            category:  .food,
            createdAt: Date()
        )
        NotificationStore.shared.merge([item])

        let vm = ActivityViewModel()
        vm.items = [item]
        // Count unread from in-memory items to avoid a race against other test suites that
        // share NotificationStore.shared and may clear it on a background thread.
        vm.unreadCount = vm.items.filter { !$0.isRead }.count
        #expect(vm.unreadCount == 1)

        vm.markRead(item)
        #expect(vm.items.first?.isRead == true)
        #expect(vm.unreadCount == 0)

        vm.delete(item)
        #expect(vm.items.isEmpty)
        #expect(NotificationStore.shared.loadAll().isEmpty)
    }
}

// MARK: - NotificationItem Codable round-trip

@Suite("NotificationItem — Codable")
struct NotificationItemCodableTests {

    @Test("expense item survives encode/decode round-trip")
    func expenseRoundTrip() throws {
        let original = NotificationItem(
            id:        UUID(),
            eventType: .expenseAdded,
            title:     "Hotel",
            subtitle:  "✈️ Trip · Paid by Alice",
            amount:    120.00,
            currency:  "EUR",
            category:  .accommodation,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let data    = try encoder.encode(original)
        let decoded = try decoder.decode(NotificationItem.self, from: data)

        #expect(decoded.id        == original.id)
        #expect(decoded.eventType == original.eventType)
        #expect(decoded.title     == original.title)
        #expect(decoded.amount    == original.amount)
        #expect(decoded.currency  == original.currency)
        #expect(decoded.category  == original.category)
        #expect(decoded.isRead    == original.isRead)
    }

    @Test("settlement item survives encode/decode round-trip")
    func settlementRoundTrip() throws {
        let original = NotificationItem(
            id:        UUID(),
            eventType: .settlementMade,
            title:     "Bob settled up",
            subtitle:  "✈️ Trip · Paid Alice",
            amount:    45.00,
            currency:  "GBP",
            category:  .other,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NotificationItem.self, from: data)

        #expect(decoded.eventType == .settlementMade)
        #expect(decoded.title     == "Bob settled up")
    }
}

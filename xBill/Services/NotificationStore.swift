//
//  NotificationStore.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

// MARK: - NotificationStore
// Local-first persistence for in-app notification history.
// All items survive offline / killed-app restarts via App Group UserDefaults.
// Read state is stored per item. lastViewedAt remains for older data/logic compatibility.

final class NotificationStore: @unchecked Sendable {
    static let shared = NotificationStore()
    private init() {}

    private let itemsKey      = "xbill_notifications_v1"
    private let lastViewedKey = "xbill_notifications_last_viewed"
    private let maxCount      = 100

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    // MARK: - Items

    func loadAll() -> [NotificationItem] {
        guard let raw = CacheService.defaults.data(forKey: itemsKey) else { return [] }
        let data = CacheService.decrypt(raw) ?? raw
        guard let items = try? decoder.decode([NotificationItem].self, from: data) else { return [] }
        return items
    }

    /// Merges new items into the store, deduplicating by id.
    /// Existing items keep their current isRead state.
    func merge(_ newItems: [NotificationItem]) {
        var existing    = loadAll()
        let existingIDs = Set(existing.map(\.id))
        let toAdd       = newItems.filter { !existingIDs.contains($0.id) }
        existing.insert(contentsOf: toAdd, at: 0)
        save(existing)
    }

    func delete(id: UUID) {
        save(loadAll().filter { $0.id != id })
    }

    func clearItems() {
        CacheService.defaults.removeObject(forKey: itemsKey)
    }

    // MARK: - Read tracking

    func lastViewedAt() -> Date {
        let ts = CacheService.defaults.double(forKey: lastViewedKey)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : .distantPast
    }

    func markAllRead() {
        let updated = loadAll().map { item in
            var copy = item
            copy.isRead = true
            return copy
        }
        save(updated)
        CacheService.defaults.set(Date().timeIntervalSince1970, forKey: lastViewedKey)
    }

    func markRead(id: UUID) {
        updateReadState(id: id, isRead: true)
    }

    func markUnread(id: UUID) {
        updateReadState(id: id, isRead: false)
    }

    func unreadCount() -> Int {
        loadAll().filter { !$0.isRead }.count
    }

    // MARK: - Test support

    func clearAll() {
        CacheService.defaults.removeObject(forKey: itemsKey)
        CacheService.defaults.removeObject(forKey: lastViewedKey)
    }

    // MARK: - Private

    private func updateReadState(id: UUID, isRead: Bool) {
        let updated = loadAll().map { item in
            guard item.id == id else { return item }
            var copy = item
            copy.isRead = isRead
            return copy
        }
        save(updated)
    }

    private func save(_ items: [NotificationItem]) {
        let capped = Array(items.sorted { $0.createdAt > $1.createdAt }.prefix(maxCount))
        guard let plain = try? encoder.encode(capped) else { return }
        let data = CacheService.encrypt(plain) ?? plain
        CacheService.defaults.set(data, forKey: itemsKey)
    }
}

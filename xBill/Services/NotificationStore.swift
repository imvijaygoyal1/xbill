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

    // Serialises all read-modify-write cycles to prevent TOCTOU races when
    // multiple tasks call merge/markRead/delete concurrently.
    private let lock = NSLock()

    // MARK: - Items

    func loadAll() -> [NotificationItem] {
        lock.withLock { _loadAll() }
    }

    /// Merges new items into the store, deduplicating by id.
    /// Existing items keep their current isRead state.
    func merge(_ newItems: [NotificationItem]) {
        lock.withLock {
            var existing    = _loadAll()
            let existingIDs = Set(existing.map(\.id))
            // M-27: deduplicate within newItems first (e.g. same expense fetched from
            // parallel group requests), then filter against already-stored IDs.
            var seen = Set<UUID>()
            let uniqueNew = newItems.filter { seen.insert($0.id).inserted }
            let toAdd       = uniqueNew.filter { !existingIDs.contains($0.id) }
            existing.insert(contentsOf: toAdd, at: 0)
            _save(existing)
        }
    }

    func delete(id: UUID) {
        lock.withLock { _save(_loadAll().filter { $0.id != id }) }
    }

    func clearItems() {
        lock.withLock { CacheService.defaults.removeObject(forKey: itemsKey) }
    }

    // MARK: - Read tracking

    func lastViewedAt() -> Date {
        let ts = CacheService.defaults.double(forKey: lastViewedKey)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : .distantPast
    }

    func markAllRead() {
        lock.withLock {
            let updated = _loadAll().map { item -> NotificationItem in
                var copy = item
                copy.isRead = true
                return copy
            }
            _save(updated)
            CacheService.defaults.set(Date().timeIntervalSince1970, forKey: lastViewedKey)
        }
    }

    func markRead(id: UUID) {
        lock.withLock { _updateReadState(id: id, isRead: true) }
    }

    func markUnread(id: UUID) {
        lock.withLock { _updateReadState(id: id, isRead: false) }
    }

    func unreadCount() -> Int {
        lock.withLock { _loadAll().filter { !$0.isRead }.count }
    }

    // MARK: - Test support

    func clearAll() {
        lock.withLock {
            CacheService.defaults.removeObject(forKey: itemsKey)
            CacheService.defaults.removeObject(forKey: lastViewedKey)
        }
    }

    // MARK: - Private (must be called inside lock)

    private func _updateReadState(id: UUID, isRead: Bool) {
        let updated = _loadAll().map { item -> NotificationItem in
            guard item.id == id else { return item }
            var copy = item
            copy.isRead = isRead
            return copy
        }
        _save(updated)
    }

    private func _loadAll() -> [NotificationItem] {
        guard let raw = CacheService.defaults.data(forKey: itemsKey) else { return [] }
        let data = CacheService.decrypt(raw) ?? raw
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let items = try? decoder.decode([NotificationItem].self, from: data) else { return [] }
        return items
    }

    private func _save(_ items: [NotificationItem]) {
        let capped = Array(items.sorted { $0.createdAt > $1.createdAt }.prefix(maxCount))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let plain = try? encoder.encode(capped) else { return }
        let data = CacheService.encrypt(plain) ?? plain
        CacheService.defaults.set(data, forKey: itemsKey)
    }
}

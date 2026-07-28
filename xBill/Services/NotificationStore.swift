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

    private let itemsKey: String
    private let lastViewedKey: String
    private let maxCount      = 100

    init(
        itemsKey: String = "xbill_notifications_v1",
        lastViewedKey: String = "xbill_notifications_last_viewed"
    ) {
        self.itemsKey = itemsKey
        self.lastViewedKey = lastViewedKey
    }

    // Serialises all read-modify-write cycles to prevent TOCTOU races when
    // multiple tasks call merge/markRead/delete concurrently.
    private let lock = NSLock()

    // MARK: - Items

    func loadAll(userID: UUID? = nil) -> [NotificationItem] {
        lock.withLock { _loadAll(userID: userID) }
    }

    /// Merges new items into the store, deduplicating by id.
    /// Existing items keep their current isRead state.
    func merge(_ newItems: [NotificationItem], userID: UUID? = nil) {
        lock.withLock {
            var existing    = _loadAll(userID: userID)
            let existingIDs = Set(existing.map(\.id))
            // M-27: deduplicate within newItems first (e.g. same expense fetched from
            // parallel group requests), then filter against already-stored IDs.
            var seen = Set<UUID>()
            let uniqueNew = newItems.filter { seen.insert($0.id).inserted }
            let toAdd       = uniqueNew.filter { !existingIDs.contains($0.id) }
            existing.insert(contentsOf: toAdd, at: 0)
            _save(existing, userID: userID)
        }
    }

    /// Reconciles server state while preserving local-only items created before
    /// the server-backed notification table was deployed.
    func mergeRemote(_ remoteItems: [NotificationItem], userID: UUID? = nil) {
        lock.withLock {
            var existing = _loadAll(userID: userID)
            var indexByID = Dictionary(uniqueKeysWithValues: existing.enumerated().map { ($0.element.id, $0.offset) })
            for item in remoteItems {
                if let index = indexByID[item.id] {
                    existing[index] = item
                } else {
                    indexByID[item.id] = existing.count
                    existing.append(item)
                }
            }
            _save(existing, userID: userID)
        }
    }

    /// Replaces the cache after a successful authoritative server fetch. This
    /// removes pre-migration local-only entries that have no server event.
    func replaceWithRemote(_ remoteItems: [NotificationItem], userID: UUID? = nil) {
        lock.withLock { _save(remoteItems, userID: userID) }
    }

    func delete(id: UUID, userID: UUID? = nil) {
        lock.withLock { _save(_loadAll(userID: userID).filter { $0.id != id }, userID: userID) }
    }

    // MARK: - Read tracking

    func lastViewedAt(userID: UUID? = nil) -> Date {
        let ts = CacheService.defaults.double(forKey: key(lastViewedKey, userID: userID))
        return ts > 0 ? Date(timeIntervalSince1970: ts) : .distantPast
    }

    func markAllRead(userID: UUID? = nil) {
        lock.withLock {
            let updated = _loadAll(userID: userID).map { item -> NotificationItem in
                var copy = item
                copy.isRead = true
                return copy
            }
            _save(updated, userID: userID)
            CacheService.defaults.set(Date().timeIntervalSince1970, forKey: key(lastViewedKey, userID: userID))
        }
    }

    func markRead(id: UUID, userID: UUID? = nil) {
        lock.withLock { _updateReadState(id: id, isRead: true, userID: userID) }
    }

    func markUnread(id: UUID, userID: UUID? = nil) {
        lock.withLock { _updateReadState(id: id, isRead: false, userID: userID) }
    }

    func unreadCount(userID: UUID? = nil) -> Int {
        lock.withLock { _loadAll(userID: userID).filter { !$0.isRead }.count }
    }

    // MARK: - Test support

    func clearAll() {
        lock.withLock {
            CacheService.defaults.removeObject(forKey: itemsKey)
            CacheService.defaults.removeObject(forKey: lastViewedKey)
        }
    }

    // MARK: - Private (must be called inside lock)

    private func _updateReadState(id: UUID, isRead: Bool, userID: UUID?) {
        let updated = _loadAll(userID: userID).map { item -> NotificationItem in
            guard item.id == id else { return item }
            var copy = item
            copy.isRead = isRead
            return copy
        }
        _save(updated, userID: userID)
    }

    private func key(_ base: String, userID: UUID?) -> String {
        guard let userID else { return base }
        return "\(base)_user_\(userID.uuidString.lowercased())"
    }

    private func _loadAll(userID: UUID?) -> [NotificationItem] {
        guard let raw = CacheService.defaults.data(forKey: key(itemsKey, userID: userID)) else { return [] }
        let data = CacheService.decrypt(raw) ?? raw
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let items = try? decoder.decode([NotificationItem].self, from: data) else { return [] }
        return items
    }

    private func _save(_ items: [NotificationItem], userID: UUID?) {
        let capped = Array(items.sorted { $0.createdAt > $1.createdAt }.prefix(maxCount))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let plain = try? encoder.encode(capped) else { return }
        let data = CacheService.encrypt(plain) ?? plain
        CacheService.defaults.set(data, forKey: key(itemsKey, userID: userID))
    }
}

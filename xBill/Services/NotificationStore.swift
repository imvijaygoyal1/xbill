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
// Read state is tracked per session via lastViewedAt timestamp.

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
        guard let data  = CacheService.defaults.data(forKey: itemsKey),
              let items = try? decoder.decode([NotificationItem].self, from: data)
        else { return [] }
        return items
    }

    /// Merges new items into the store, deduplicating by id.
    /// Existing items keep their current isRead state.
    func merge(_ newItems: [NotificationItem]) {
        var existing    = loadAll()
        let existingIDs = Set(existing.map(\.id))
        let toAdd       = newItems.filter { !existingIDs.contains($0.id) }
        existing.insert(contentsOf: toAdd, at: 0)
        existing = Array(existing.sorted { $0.createdAt > $1.createdAt }.prefix(maxCount))
        guard let data = try? encoder.encode(existing) else { return }
        CacheService.defaults.set(data, forKey: itemsKey)
    }

    // MARK: - Read tracking

    func lastViewedAt() -> Date {
        let ts = CacheService.defaults.double(forKey: lastViewedKey)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : .distantPast
    }

    func markAllRead() {
        CacheService.defaults.set(Date().timeIntervalSince1970, forKey: lastViewedKey)
    }

    func unreadCount() -> Int {
        let lastViewed = lastViewedAt()
        return loadAll().filter { $0.createdAt > lastViewed }.count
    }

    // MARK: - Test support

    func clearAll() {
        CacheService.defaults.removeObject(forKey: itemsKey)
        CacheService.defaults.removeObject(forKey: lastViewedKey)
    }
}

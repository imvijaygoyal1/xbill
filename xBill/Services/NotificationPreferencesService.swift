//
//  NotificationPreferencesService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  PUSH-01. Which push notifications **you** receive, stored where the sender's device cannot
//  reach it.
//
//  The Profile toggles used to write `UserDefaults` keys that were then read on the **sender's**
//  device to decide whether *other people* got notified — so "New Expenses" turned off meant
//  "nobody in my groups hears when I add an expense", and the recipient's own choice was never
//  consulted by anything. It could not be: the only place that can honour a recipient's
//  preference is the server.
//
//  `UserDefaults` is still written, but demoted to an **offline cache** so the toggles render the
//  right way round on launch before the network answers. The server row is authoritative.
//

import Foundation
import OSLog

struct NotificationPreferences: Codable, Sendable, Equatable {
    var expenses: Bool
    var settlements: Bool
    var comments: Bool
    var friendRequests: Bool

    /// What a user with no row has. Matches migration 049's column defaults **and** the Edge
    /// Functions' treatment of a missing row, which must agree — if they drift, the app shows a
    /// state the server does not implement.
    static let `default` = NotificationPreferences(
        expenses: true, settlements: true, comments: true, friendRequests: true
    )

    enum CodingKeys: String, CodingKey {
        case expenses
        case settlements
        case comments
        case friendRequests = "friend_requests"
    }

    /// The four categories, so UI and cache cannot disagree about the set.
    enum Category: String, CaseIterable, Sendable {
        case expenses, settlements, comments
        case friendRequests = "friend_requests"

        var cacheKey: String { "prefPush_\(rawValue)" }
    }

    subscript(category: Category) -> Bool {
        get {
            switch category {
            case .expenses:       expenses
            case .settlements:    settlements
            case .comments:       comments
            case .friendRequests: friendRequests
            }
        }
        set {
            switch category {
            case .expenses:       expenses = newValue
            case .settlements:    settlements = newValue
            case .comments:       comments = newValue
            case .friendRequests: friendRequests = newValue
            }
        }
    }
}

@MainActor
final class NotificationPreferencesService {
    static let shared = NotificationPreferencesService()
    private let supabase = SupabaseManager.shared
    private let log = Logger(subsystem: "com.vijaygoyal.xbill", category: "NotificationPreferences")

    private init() {}

    // MARK: - Local cache

    /// Last known preferences, for rendering before the network answers.
    ///
    /// Defaults to `.default` (everything on) for a user who has never had a row — the same thing
    /// the server does — rather than to `false`, which is what `xBillApp` used to register and is
    /// how a brand-new user came to suppress notifications for everyone they shared a group with.
    nonisolated static var cached: NotificationPreferences {
        var prefs = NotificationPreferences.default
        for category in NotificationPreferences.Category.allCases
        where CacheService.defaults.object(forKey: category.cacheKey) != nil {
            prefs[category] = CacheService.defaults.bool(forKey: category.cacheKey)
        }
        return prefs
    }

    nonisolated static func cache(_ prefs: NotificationPreferences) {
        for category in NotificationPreferences.Category.allCases {
            CacheService.defaults.set(prefs[category], forKey: category.cacheKey)
        }
    }

    // MARK: - Server

    /// The authoritative row, or `.default` when the user has none yet.
    ///
    /// A missing row is **not** an error and must not be reported as one: it is the normal state
    /// for every account that predates migration 049, which is all of them. Hence `.limit(1)` and
    /// an array decode rather than `.single()` — `.single()` raises `PGRST116` on zero rows, the
    /// mistake that made a zero-row notification update look like a response-shape fault
    /// (`NOTIF-01`).
    func fetch(userID: UUID) async throws -> NotificationPreferences {
        let rows: [NotificationPreferences] = try await supabase.table("notification_preferences")
            .select("expenses, settlements, comments, friend_requests")
            .eq("user_id", value: userID)
            .limit(1)
            .execute()
            .value
        let prefs = rows.first ?? .default
        Self.cache(prefs)
        return prefs
    }

    /// Write one category. Upsert, because the row may not exist yet.
    func set(_ category: NotificationPreferences.Category,
             to value: Bool,
             userID: UUID) async throws {
        var prefs = Self.cached
        prefs[category] = value

        struct Row: Encodable {
            let userID: UUID
            let expenses: Bool
            let settlements: Bool
            let comments: Bool
            let friendRequests: Bool
            enum CodingKeys: String, CodingKey {
                case userID         = "user_id"
                case expenses, settlements, comments
                case friendRequests = "friend_requests"
            }
        }
        // Every column is sent, not just the changed one: an upsert that omits a column resets it
        // to the table default on insert, which would silently re-enable a category the user had
        // turned off. Swift's synthesized `Encodable` omits nothing here — all four are non-optional
        // — which is the property `SPLIT-04` needed and did not have.
        try await supabase.table("notification_preferences")
            .upsert(Row(userID: userID,
                        expenses: prefs.expenses,
                        settlements: prefs.settlements,
                        comments: prefs.comments,
                        friendRequests: prefs.friendRequests),
                    onConflict: "user_id")
            .execute()

        // Cached only after the write succeeds. Caching first would leave the toggle showing a
        // state the server never accepted, and the next launch would read it back as truth.
        Self.cache(prefs)
    }
}

//
//  NotificationPreferencesTests.swift
//  xBillTests
//
//  PUSH-01. The Profile toggle titled "New Expenses" decided whether **other people** were
//  notified when **you** added an expense, and defaulted to `false`. The recipient's own
//  preference was never consulted, and there was nowhere server-side to consult it.
//
//  What is tested here is the client half: the defaults, the decode against the real column
//  names, the cache's treatment of an absent key, and the exact wire payload of a write.
//
//  What is NOT tested here, and must not be claimed from a green run:
//    • that a muted recipient stops receiving pushes. That decision is made by the Edge
//      Functions, in TypeScript, against a live database — verified by invoking them.
//    • that any notification arrives at all. APNs does not deliver to a simulator.
//

import Testing
import Foundation
@testable import xBill

@Suite("PUSH-01 — notification preferences", .serialized)
struct NotificationPreferencesTests {

    private func clearCache() {
        for category in NotificationPreferences.Category.allCases {
            CacheService.defaults.removeObject(forKey: category.cacheKey)
        }
    }

    // MARK: - Defaults

    /// The single most consequential value in this change. `false` here is the original defect:
    /// a user who had never opened Profile suppressed notifications for their whole group.
    @Test("every category defaults to on")
    func defaultsAreOn() {
        let d = NotificationPreferences.default
        #expect(d.expenses)
        #expect(d.settlements)
        #expect(d.comments)
        #expect(d.friendRequests)
    }

    /// The client's default and the server's treatment of a missing row have to agree. If they
    /// drift, Profile shows a state the Edge Functions do not implement — and the user cannot
    /// tell, because the only symptom is a notification that does or does not arrive.
    ///
    /// Asserts the **values**, not `== .default`. The first version compared against `.default`
    /// and therefore passed against a mutant with every default flipped to `false` — the two moved
    /// together, so it could not distinguish the fix from the exact bug it exists to prevent. Same
    /// flaw as `warningPenalises` in `SCAN-02`.
    @Test("an absent cache entry reads as on, matching a missing server row")
    func absentCacheReadsAsOn() {
        clearCache()
        defer { clearCache() }

        let cached = NotificationPreferencesService.cached
        #expect(cached.expenses)
        #expect(cached.settlements)
        #expect(cached.comments)
        #expect(cached.friendRequests)
    }

    @Test("a cached false survives, and only for its own category")
    func cachedValueIsRespected() {
        clearCache()
        defer { clearCache() }

        var prefs = NotificationPreferences.default
        prefs.comments = false
        NotificationPreferencesService.cache(prefs)

        let read = NotificationPreferencesService.cached
        #expect(read.comments == false)
        #expect(read.expenses)          // untouched categories must not be dragged along
        #expect(read.settlements)
        #expect(read.friendRequests)
    }

    // MARK: - Wire format

    /// Decoded through the decoder PostgREST actually uses, against the column names migration
    /// 049 creates. `friend_requests` is the one that can silently drift — Swift would happily
    /// decode `friendRequests` from a key that does not exist by throwing, and a `try?` anywhere
    /// upstream would turn that into "all defaults, everything on".
    @Test("decodes the server's snake_case columns")
    func decodesServerColumns() throws {
        let json = """
        {"expenses": true, "settlements": false, "comments": true, "friend_requests": false}
        """.data(using: .utf8)!
        let prefs = try SupabaseManager.postgrestDecoder
            .decode(NotificationPreferences.self, from: json)

        #expect(prefs.expenses)
        #expect(prefs.settlements == false)
        #expect(prefs.comments)
        #expect(prefs.friendRequests == false)
    }

    /// A missing column must fail loudly rather than default to on. Silently substituting `true`
    /// for a column that did not arrive is how a mute would be lost without any error.
    @Test("a payload missing a column fails to decode rather than defaulting")
    func missingColumnDoesNotSilentlyDefault() {
        let json = """
        {"expenses": true, "settlements": true, "comments": true}
        """.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try SupabaseManager.postgrestDecoder.decode(NotificationPreferences.self, from: json)
        }
    }

    // MARK: - Category mapping

    /// The subscript is what keeps the four toggles, the four columns and the four cache keys in
    /// step. A copy-paste slip here would write one category's value into another's row — a
    /// defect whose only symptom is the wrong notification going quiet.
    @Test("each category reads and writes only itself")
    func subscriptIsOneToOne() {
        for category in NotificationPreferences.Category.allCases {
            var prefs = NotificationPreferences.default
            prefs[category] = false

            #expect(prefs[category] == false, "\(category.rawValue) did not take its own value")
            for other in NotificationPreferences.Category.allCases where other != category {
                #expect(prefs[other], "setting \(category.rawValue) also changed \(other.rawValue)")
            }
        }
    }

    /// The raw values are the column names in migration 049 and the `PreferenceColumn` union in
    /// `_shared/apns.ts`. Three places, one spelling, and nothing else checks it.
    @Test("category raw values are the database column names")
    func rawValuesMatchColumns() {
        #expect(Set(NotificationPreferences.Category.allCases.map(\.rawValue))
                == ["expenses", "settlements", "comments", "friend_requests"])
    }
}

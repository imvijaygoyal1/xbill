//
//  SupabaseWrite.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Shared affected-row acknowledgement for PostgREST writes.
//
//  A write that matches no row returns HTTP 200 with an empty body, so an `update`/`delete`
//  without this check reports success when RLS denied it or the row was already gone. That
//  produced NOTIF-04 (a read-state write against an id that was not a notification row) and
//  the same latent fault existed on five delete paths — REV-06.
//
//  `.single()` is deliberately not used anywhere for this. It only sets
//  `Accept: application/vnd.pgrst.object+json`; on a zero-row match PostgREST answers
//  PGRST116 "Cannot coerce the result to a single JSON object", which reads as a
//  response-shape fault and hides the real cause. `Prefer: return=representation` — which
//  `.select()` sets — answers with a JSON array, so counting it is the reliable signal.
//

import Foundation

/// A single `id` column from a `return=representation` response.
struct AffectedRowID: Decodable, Equatable {
    let id: UUID
}

enum SupabaseWriteError: LocalizedError, Equatable {
    /// The write matched no row: it was already gone, or RLS hid it from this user.
    case noRowsAffected(table: String, id: UUID)

    var errorDescription: String? {
        switch self {
        case .noRowsAffected(let table, _):
            return "This \(Self.subject(for: table)) could not be updated. It may have been removed, or you may not have permission to change it."
        }
    }

    private static func subject(for table: String) -> String {
        switch table {
        case "expenses":      return "expense"
        case "groups":        return "group"
        case "comments":      return "comment"
        case "ious":          return "IOU"
        case "friends":       return "friend"
        case "splits":        return "split"
        case "notifications": return "notification"
        default:              return "record"
        }
    }
}

enum SupabaseWrite {
    /// Throws when a write affected no rows.
    ///
    /// Only use this where zero rows genuinely means failure. Some writes legitimately match
    /// nothing — clearing a user's device tokens when they have none, for example — and must
    /// not be routed through here.
    static func requireAffected(_ rows: [AffectedRowID], table: String, id: UUID) throws {
        guard !rows.isEmpty else {
            throw SupabaseWriteError.noRowsAffected(table: table, id: id)
        }
    }
}

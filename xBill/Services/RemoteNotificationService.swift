//
//  RemoteNotificationService.swift
//  xBill
//

import Foundation

// MARK: - Read-state wire types

/// The body of a read-state PATCH.
///
/// Two wire details are load-bearing:
///
/// - Swift's synthesized `Encodable` omits nil optionals, and a PATCH without the key is a
///   no-op that can never clear `read_at`. The explicit `encode` below always writes the
///   key, so an unread transition sends a JSON null.
/// - The timestamp is written as an explicit UTC instant. The SDK's own date strategy emits
///   a zone-less string (`2023-11-14T22:13:20.000`), which Postgres resolves using the
///   session `TimeZone`. That is UTC on this project today, but the read time should not
///   depend on a server setting.
struct NotificationReadStatePayload: Encodable {
    let readAt: Date?

    enum CodingKeys: String, CodingKey { case readAt = "read_at" }

    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(readAt.map(Self.formatter.string(from:)), forKey: .readAt)
    }
}

@MainActor
final class RemoteNotificationService {
    static let shared = RemoteNotificationService()
    private let supabase = SupabaseManager.shared

    private init() {}

    private struct Row: Decodable {
        let id: UUID
        let eventType: NotificationEventType
        let title: String
        let subtitle: String
        let amount: Decimal
        let currency: String
        let category: Expense.Category
        let groupID: UUID?
        let expenseID: UUID?
        let createdAt: Date
        let readAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, title, subtitle, amount, currency, category
            case eventType = "event_type"
            case groupID = "group_id"
            case expenseID = "expense_id"
            case createdAt = "created_at"
            case readAt = "read_at"
        }
    }

    func fetch(userID: UUID, limit: Int = 100) async throws -> [NotificationItem] {
        let rows: [Row] = try await supabase.table("notifications")
            .select()
            .eq("recipient_id", value: userID)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return rows.map {
            .remote(
                id: $0.id,
                eventType: $0.eventType,
                title: $0.title,
                subtitle: $0.subtitle,
                amount: $0.amount,
                currency: $0.currency,
                category: $0.category,
                createdAt: $0.createdAt,
                isRead: $0.readAt != nil,
                groupID: $0.groupID,
                expenseID: $0.expenseID
            )
        }
    }

    func markRead(id: UUID) async throws {
        try await updateReadState(id: id, readAt: Date())
    }

    func markUnread(id: UUID) async throws {
        try await updateReadState(id: id, readAt: nil)
    }

    private func updateReadState(id: UUID, readAt: Date?) async throws {
        let rows: [AffectedRowID] = try await supabase.table("notifications")
            .update(NotificationReadStatePayload(readAt: readAt))
            .eq("id", value: id)
            .select("id")
            .execute()
            .value
        try SupabaseWrite.requireAffected(rows, table: "notifications", id: id)
    }

    func markAllRead(userID: UUID) async throws {
        struct Payload: Encodable { let readAt: Date; enum CodingKeys: String, CodingKey { case readAt = "read_at" } }
        try await supabase.table("notifications")
            .update(Payload(readAt: Date()))
            .eq("recipient_id", value: userID)
            .is("read_at", value: nil)
            .execute()
    }

    /// Deletes take the same affected-row acknowledgement as the read-state update: without
    /// it an RLS miss or an id that is not a notification row returns HTTP 200 with an empty
    /// body, the row disappears locally, and the next fetch brings it straight back.
    func delete(id: UUID) async throws {
        let rows: [AffectedRowID] = try await supabase.table("notifications")
            .delete()
            .eq("id", value: id)
            .select("id")
            .execute()
            .value
        try SupabaseWrite.requireAffected(rows, table: "notifications", id: id)
    }

    func unreadCount(userID: UUID) async throws -> Int {
        let response = try await supabase.table("notifications")
            .select("id", head: true, count: .exact)
            .eq("recipient_id", value: userID)
            .is("read_at", value: nil)
            .execute()
        return response.count ?? 0
    }
}

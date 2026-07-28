//
//  RemoteNotificationService.swift
//  xBill
//

import Foundation

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
        struct Payload: Encodable { let readAt: Date?; enum CodingKeys: String, CodingKey { case readAt = "read_at" } }
        try await supabase.table("notifications")
            .update(Payload(readAt: readAt))
            .eq("id", value: id)
            .execute()
    }

    func markAllRead(userID: UUID) async throws {
        struct Payload: Encodable { let readAt: Date; enum CodingKeys: String, CodingKey { case readAt = "read_at" } }
        try await supabase.table("notifications")
            .update(Payload(readAt: Date()))
            .eq("recipient_id", value: userID)
            .is("read_at", value: nil)
            .execute()
    }

    func delete(id: UUID) async throws {
        try await supabase.table("notifications")
            .delete()
            .eq("id", value: id)
            .execute()
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

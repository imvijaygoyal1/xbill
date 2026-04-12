import Foundation
import Supabase

final class CommentService: Sendable {
    static let shared = CommentService()
    private let supabase = SupabaseManager.shared
    private init() {}

    // MARK: - Fetch

    func fetchComments(expenseID: UUID) async throws -> [Comment] {
        try await supabase.table("comments")
            .select()
            .eq("expense_id", value: expenseID)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    // MARK: - Create

    func addComment(expenseID: UUID, userID: UUID, text: String) async throws -> Comment {
        struct Payload: Encodable {
            let expenseID: UUID
            let userID: UUID
            let text: String
            enum CodingKeys: String, CodingKey {
                case expenseID = "expense_id"
                case userID    = "user_id"
                case text
            }
        }
        return try await supabase.table("comments")
            .insert(Payload(expenseID: expenseID, userID: userID, text: text))
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Delete

    func deleteComment(id: UUID) async throws {
        try await supabase.table("comments")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Realtime

    /// Streams a signal whenever any comment on the given expense changes.
    func commentChanges(expenseID: UUID) async throws -> AsyncStream<Void> {
        let channel = supabase.client.channel("comments-\(expenseID.uuidString)")
        let stream  = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table:  "comments",
            filter: "expense_id=eq.\(expenseID.uuidString)"
        )
        try await channel.subscribe()
        return AsyncStream { continuation in
            Task {
                for await _ in stream { continuation.yield() }
                continuation.finish()
            }
        }
    }
}

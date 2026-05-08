//
//  CommentService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

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

    func addComment(
        expenseID:     UUID,
        userID:        UUID,
        text:          String,
        expenseTitle:  String,
        groupID:       UUID,
        groupName:     String,
        commenterName: String
    ) async throws -> Comment {
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
        let comment: Comment = try await supabase.table("comments")
            .insert(Payload(expenseID: expenseID, userID: userID, text: text))
            .select()
            .single()
            .execute()
            .value
        // M-21: use App Group suite so the preference is shared with the widget extension,
        // consistent with all other push-preference reads in the app.
        if (UserDefaults(suiteName: "group.com.vijaygoyal.xbill") ?? .standard).bool(forKey: "prefPushComment") {
            Task {
                await notifyComment(
                    expenseID:     expenseID,
                    expenseTitle:  expenseTitle,
                    groupID:       groupID,
                    groupName:     groupName,
                    commenterID:   userID,
                    commenterName: commenterName,
                    commentText:   text
                )
            }
        }
        return comment
    }

    private func notifyComment(
        expenseID:     UUID,
        expenseTitle:  String,
        groupID:       UUID,
        groupName:     String,
        commenterID:   UUID,
        commenterName: String,
        commentText:   String
    ) async {
        struct Payload: Encodable {
            let expenseId, expenseTitle, groupId, groupName: String
            let commenterID, commenterName, commentText: String
            let isDevelopment: Bool
        }
        #if DEBUG
        let dev = true
        #else
        let dev = false
        #endif
        let payload = Payload(
            expenseId:     expenseID.uuidString,
            expenseTitle:  expenseTitle,
            groupId:       groupID.uuidString,
            groupName:     groupName,
            commenterID:   commenterID.uuidString,
            commenterName: commenterName,
            commentText:   commentText,
            isDevelopment: dev
        )
        _ = try? await supabase.client.functions
            .invoke("notify-comment", options: .init(body: payload))
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
        let topic = "comments-\(expenseID.uuidString)"
        // Remove any existing subscribed channel before registering new callbacks.
        let stale = supabase.client.channel(topic)
        await supabase.client.removeChannel(stale)

        let channel = supabase.client.channel(topic)
        let stream  = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table:  "comments",
            filter: "expense_id=eq.\(expenseID.uuidString)"
        )
        try await channel.subscribeWithError()
        let client = supabase.client
        return AsyncStream { continuation in
            // M-17: retain the task handle so it is cancelled when the stream terminates.
            // Without this the inner Task outlives its consumer.
            let t = Task {
                for await _ in stream { continuation.yield() }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                t.cancel()
                Task { await client.removeChannel(channel) }
            }
        }
    }
}

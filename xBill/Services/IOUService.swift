//
//  IOUService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Supabase

final class IOUService: Sendable {
    static let shared = IOUService()
    private let supabase = SupabaseManager.shared
    private init() {}

    // MARK: - Fetch

    /// Fetches all IOUs where the user is either lender or borrower.
    /// Single query guarantees both sides come from the same DB snapshot.
    func fetchIOUs(userID: UUID) async throws -> [IOU] {
        let uid = userID.uuidString
        return try await supabase.table("ious")
            .select()
            .or("lender_id.eq.\(uid),borrower_id.eq.\(uid)")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Looks up a user profile by exact email address.
    /// Uses lookup_profiles_by_email SECURITY DEFINER RPC (same as FriendService)
    /// to prevent full-table email enumeration by authenticated users.
    func fetchUserByEmail(_ email: String) async throws -> User? {
        struct Row: Decodable {
            let id: UUID
            let displayName: String
            let avatarURL: URL?
            let createdAt: Date
            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
                case avatarURL   = "avatar_url"
                case createdAt   = "created_at"
            }
        }
        struct Params: Encodable { let p_emails: [String] }
        let normalised = email.lowercased().trimmingCharacters(in: .whitespaces)
        let rows: [Row] = try await supabase.client
            .rpc("lookup_profiles_by_email", params: Params(p_emails: [normalised]))
            .execute()
            .value
        guard let row = rows.first else { return nil }
        return User(id: row.id, email: normalised,
                    displayName: row.displayName, avatarURL: row.avatarURL,
                    createdAt: row.createdAt)
    }

    // MARK: - Create

    func createIOU(
        createdBy:   UUID,
        lenderID:    UUID,
        borrowerID:  UUID,
        amount:      Decimal,
        currency:    String,
        description: String?
    ) async throws -> IOU {
        struct Payload: Encodable {
            let createdBy:   UUID
            let lenderID:    UUID
            let borrowerID:  UUID
            let amount:      Decimal
            let currency:    String
            let description: String?
            enum CodingKeys: String, CodingKey {
                case createdBy   = "created_by"
                case lenderID    = "lender_id"
                case borrowerID  = "borrower_id"
                case amount, currency, description
            }
        }
        return try await supabase.table("ious")
            .insert(Payload(
                createdBy: createdBy, lenderID: lenderID, borrowerID: borrowerID,
                amount: amount, currency: currency, description: description
            ))
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Settle

    func settleIOU(id: UUID) async throws {
        struct Payload: Encodable { let isSettled = true; enum CodingKeys: String, CodingKey { case isSettled = "is_settled" } }
        try await supabase.table("ious")
            .update(Payload())
            .eq("id", value: id)
            .execute()
    }

    // M-26: No in-service concurrency guard against double-settling.
    // `final class: Sendable` cannot safely hold mutable debounce state.
    // The `!$0.isSettled` filter provides DB-level idempotency (settling an already-settled
    // IOU is a no-op in practice), but if the user taps "Settle" and "Settle All"
    // simultaneously both calls may read the same snapshot before either write completes.
    // Callers (ViewModels) MUST disable their settle buttons while the async call is in flight
    // to prevent duplicate concurrent invocations.
    func settleAllIOUs(with otherUserID: UUID, currentUserID: UUID) async throws {
        let all = try await fetchIOUs(userID: currentUserID)
        let toSettle = all.filter {
            !$0.isSettled &&
            ($0.lenderID == otherUserID || $0.borrowerID == otherUserID)
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for iou in toSettle {
                group.addTask { try await self.settleIOU(id: iou.id) }
            }
            try await group.waitForAll()
        }
    }

    // MARK: - Delete

    func deleteIOU(id: UUID) async throws {
        try await supabase.table("ious")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}

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
    func fetchIOUs(userID: UUID) async throws -> [IOU] {
        async let asLender: [IOU] = supabase.table("ious")
            .select()
            .eq("lender_id", value: userID)
            .order("created_at", ascending: false)
            .execute()
            .value

        async let asBorrower: [IOU] = supabase.table("ious")
            .select()
            .eq("borrower_id", value: userID)
            .order("created_at", ascending: false)
            .execute()
            .value

        let (lender, borrower) = try await (asLender, asBorrower)
        // Deduplicate (shouldn't overlap but be safe)
        var seen = Set<UUID>()
        return (lender + borrower)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Looks up a user profile by exact email address.
    func fetchUserByEmail(_ email: String) async throws -> User? {
        let users: [User] = try await supabase.table("profiles")
            .select()
            .eq("email", value: email.lowercased().trimmingCharacters(in: .whitespaces))
            .limit(1)
            .execute()
            .value
        return users.first
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

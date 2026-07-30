//
//  SettlementService.swift
//  xBill
//

import Foundation

/// The body of a settlement INSERT. `id` and `created_at` are server defaults.
struct SettlementInsert: Encodable {
    let groupID: UUID
    let fromUserID: UUID
    let toUserID: UUID
    let amount: Decimal
    let currency: String
    let recordedBy: UUID

    enum CodingKeys: String, CodingKey {
        case amount, currency
        case groupID    = "group_id"
        case fromUserID = "from_user_id"
        case toUserID   = "to_user_id"
        case recordedBy = "recorded_by"
    }
}

@MainActor
protocol SettlementDataProviding: AnyObject, Sendable {
    func fetchSettlements(groupID: UUID) async throws -> [Settlement]
    func recordSettlement(
        groupID: UUID, fromUserID: UUID, toUserID: UUID,
        amount: Decimal, currency: String, recordedBy: UUID
    ) async throws -> Settlement
    func deleteSettlement(id: UUID) async throws
}

@MainActor
final class SettlementService: SettlementDataProviding {
    static let shared = SettlementService()
    private let supabase = SupabaseManager.shared
    private init() {}

    func fetchSettlements(groupID: UUID) async throws -> [Settlement] {
        try await supabase.table("settlements")
            .select()
            .eq("group_id", value: groupID)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Returns the inserted row. `.select().single()` is correct here — an INSERT that
    /// succeeds returns exactly one row, and a row is genuinely required by the caller.
    /// Contrast the delete below, where zero rows is the failure being detected.
    func recordSettlement(
        groupID: UUID, fromUserID: UUID, toUserID: UUID,
        amount: Decimal, currency: String, recordedBy: UUID
    ) async throws -> Settlement {
        try await supabase.table("settlements")
            .insert(SettlementInsert(
                groupID: groupID, fromUserID: fromUserID, toUserID: toUserID,
                amount: amount, currency: currency, recordedBy: recordedBy))
            .select()
            .single()
            .execute()
            .value
    }

    func deleteSettlement(id: UUID) async throws {
        let rows: [AffectedRowID] = try await supabase.table("settlements")
            .delete()
            .eq("id", value: id)
            .select("id")
            .execute()
            .value
        try SupabaseWrite.requireAffected(rows, table: "settlements", id: id)
    }
}

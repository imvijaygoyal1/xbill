//
//  ExpenseService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Supabase

// MARK: - ExpenseService

final class ExpenseService: Sendable {
    static let shared = ExpenseService()
    private let supabase = SupabaseManager.shared

    private init() {}

    // MARK: - Fetch

    func fetchExpenses(groupID: UUID) async throws -> [Expense] {
        try await supabase.table("expenses")
            .select()
            .eq("group_id", value: groupID)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchExpense(id: UUID) async throws -> Expense {
        try await supabase.table("expenses")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    func fetchSplits(expenseID: UUID) async throws -> [Split] {
        try await supabase.table("splits")
            .select()
            .eq("expense_id", value: expenseID)
            .execute()
            .value
    }

    func fetchUnsettledExpenses(groupID: UUID, userID: UUID) async throws -> [Expense] {
        // Returns expenses where the user has at least one unsettled split
        try await supabase.table("expenses")
            .select("*, splits!inner(*)")
            .eq("group_id", value: groupID)
            .eq("splits.user_id", value: userID)
            .eq("splits.is_settled", value: false)
            .execute()
            .value
    }

    // MARK: - Create

    /// Atomically inserts expense + splits using the `add_expense_with_splits` RPC.
    func createExpense(
        groupID:              UUID,
        title:                String,
        amount:               Decimal,
        currency:             String,
        payerID:              UUID,
        category:             Expense.Category,
        notes:                String?,
        receiptURL:           URL? = nil,
        splits:               [SplitInput],
        originalAmount:       Decimal? = nil,
        originalCurrency:     String?  = nil,
        recurrence:           Expense.Recurrence  = .none,
        nextOccurrenceDate:   Date?               = nil
    ) async throws -> Expense {
        let splitParams = splits.filter(\.isIncluded).map {
            RPCSplitParam(userID: $0.userID, amount: $0.amount)
        }
        let params = AddExpenseRPCParams(
            groupID:             groupID,
            paidBy:              payerID,
            amount:              amount,
            title:               title,
            category:            category.rawValue,
            currency:            currency,
            notes:               notes,
            receiptURL:          receiptURL?.absoluteString,
            splits:              splitParams,
            originalAmount:      originalAmount,
            originalCurrency:    originalCurrency,
            recurrence:          recurrence.rawValue,
            nextOccurrenceDate:  nextOccurrenceDate
        )
        return try await supabase.client.rpc("add_expense_with_splits", params: params)
            .execute()
            .value
    }

    // MARK: - Recurring

    /// Fetches recurring expenses in a group that are due (next_occurrence_date ≤ now)
    /// and where the given user is the payer.
    func fetchDueRecurringExpenses(groupID: UUID, payerID: UUID) async throws -> [Expense] {
        let nowString = ISO8601DateFormatter().string(from: Date())
        return try await supabase.table("expenses")
            .select()
            .eq("group_id",  value: groupID)
            .eq("paid_by",   value: payerID)
            .neq("recurrence", value: "none")
            .lte("next_occurrence_date", value: nowString)
            .execute()
            .value
    }

    /// Advances the `next_occurrence_date` on a template expense after spawning its instance.
    func clearNextOccurrenceDate(expenseID: UUID) async throws {
        try await supabase.table("expenses")
            .update(NullNextOccurrence())
            .eq("id", value: expenseID)
            .execute()
    }

    // MARK: - Update

    func updateExpense(_ expense: Expense) async throws -> Expense {
        try await supabase.table("expenses")
            .update(expense)
            .eq("id", value: expense.id)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Settle

    func settleSplit(id: UUID) async throws {
        let payload = SplitSettlePayload(isSettled: true, settledAt: Date())
        try await supabase.table("splits")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Notify

    func notifyExpenseAdded(
        expenseID:    UUID,
        groupID:      UUID,
        payerName:    String,
        expenseTitle: String,
        amount:       Decimal,
        currency:     String
    ) async {
        struct Payload: Encodable {
            let expenseId, groupId, payerName, expenseTitle, currency: String
            let amount: Double
        }
        let payload = Payload(
            expenseId:    expenseID.uuidString,
            groupId:      groupID.uuidString,
            payerName:    payerName,
            expenseTitle: expenseTitle,
            currency:     currency,
            amount:       NSDecimalNumber(decimal: amount).doubleValue
        )
        _ = try? await supabase.client.functions
            .invoke("notify-expense", options: .init(body: payload))
    }

    func notifySettlementRecorded(
        settlementID: UUID,
        groupID:      UUID,
        groupName:    String,
        fromUserID:   UUID,
        fromName:     String,
        toUserID:     UUID,
        amount:       Decimal,
        currency:     String
    ) async {
        struct Payload: Encodable {
            let settlementId, groupId, groupName, fromUserID, fromName, toUserID, currency: String
            let amount: Double
        }
        let payload = Payload(
            settlementId: settlementID.uuidString,
            groupId:      groupID.uuidString,
            groupName:    groupName,
            fromUserID:   fromUserID.uuidString,
            fromName:     fromName,
            toUserID:     toUserID.uuidString,
            currency:     currency,
            amount:       NSDecimalNumber(decimal: amount).doubleValue
        )
        _ = try? await supabase.client.functions
            .invoke("notify-settlement", options: .init(body: payload))
    }

    // MARK: - Delete

    func deleteExpense(id: UUID) async throws {
        try await supabase.table("expenses")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Receipt Upload

    func uploadReceiptImage(_ data: Data, expenseID: UUID) async throws -> URL {
        let path = "receipts/\(expenseID.uuidString)/\(UUID().uuidString).jpg"
        try await SupabaseManager.shared.client.storage
            .from("receipts")
            .upload(path, data: data)
        let urlString = try SupabaseManager.shared.client.storage
            .from("receipts")
            .getPublicURL(path: path)
            .absoluteString
        guard let url = URL(string: urlString) else {
            throw AppError.serverError("Invalid receipt URL returned from storage.")
        }
        return url
    }
}

// MARK: - RPC Payloads

private struct RPCSplitParam: Encodable {
    let userID: UUID
    let amount: Decimal
    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case amount
    }
}

private struct AddExpenseRPCParams: Encodable {
    let groupID:             UUID
    let paidBy:              UUID
    let amount:              Decimal
    let title:               String
    let category:            String
    let currency:            String
    let notes:               String?
    let receiptURL:          String?
    let splits:              [RPCSplitParam]
    let originalAmount:      Decimal?
    let originalCurrency:    String?
    let recurrence:          String
    let nextOccurrenceDate:  Date?
    enum CodingKeys: String, CodingKey {
        case groupID             = "p_group_id"
        case paidBy              = "p_paid_by"
        case amount              = "p_amount"
        case title               = "p_title"
        case category            = "p_category"
        case currency            = "p_currency"
        case notes               = "p_notes"
        case receiptURL          = "p_receipt_url"
        case splits              = "p_splits"
        case originalAmount      = "p_original_amount"
        case originalCurrency    = "p_original_currency"
        case recurrence          = "p_recurrence"
        case nextOccurrenceDate  = "p_next_occurrence_date"
    }
}

/// Payload that explicitly sets next_occurrence_date to null.
private struct NullNextOccurrence: Encodable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNil(forKey: .nextOccurrenceDate)
    }
    enum CodingKeys: String, CodingKey {
        case nextOccurrenceDate = "next_occurrence_date"
    }
}

private struct SplitSettlePayload: Encodable {
    let isSettled: Bool
    let settledAt: Date
    enum CodingKeys: String, CodingKey {
        case isSettled  = "is_settled"
        case settledAt  = "settled_at"
    }
}

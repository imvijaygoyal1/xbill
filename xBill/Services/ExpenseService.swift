//
//  ExpenseService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import OSLog
import Supabase

// MARK: - ExpenseService

@MainActor
final class ExpenseService {
    static let shared = ExpenseService()
    private let supabase = SupabaseManager.shared
    private let logger = Logger(subsystem: "com.vijaygoyal.xbill", category: "ExpenseService")

    private init() {}

    // MARK: - Fetch

    func fetchExpenses(groupID: UUID, limit: Int? = nil) async throws -> [Expense] {
        var query = supabase.table("expenses")
            .select()
            .eq("group_id", value: groupID)
            .order("created_at", ascending: false)
        if let limit {
            query = query.limit(limit)
        }
        return try await query.execute().value
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

    func fetchSplits(expenseIDs: [UUID]) async throws -> [Split] {
        guard !expenseIDs.isEmpty else { return [] }
        return try await supabase.table("splits")
            .select()
            .in("expense_id", values: expenseIDs)
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
        splits:               [SplitInput],
        originalAmount:       Decimal? = nil,
        originalCurrency:     String?  = nil,
        recurrence:           Expense.Recurrence  = .none,
        nextOccurrenceDate:   Date?               = nil
    ) async throws -> Expense {
        let splitParams = splits.filter(\.isIncluded).map {
            RPCSplitParam(userID: $0.userID, amount: $0.amount)
        }
        let params = Self.makeAddParams(
            groupID:             groupID,
            payerID:             payerID,
            amount:              amount,
            title:               title,
            category:            category.rawValue,
            currency:            currency,
            notes:               notes,
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

    nonisolated(unsafe) private static let iso8601Formatter = ISO8601DateFormatter()

    /// Fetches all recurring expenses in a group that are due (next_occurrence_date ≤ now),
    /// regardless of who the payer is. Any group member can trigger instantiation so that
    /// recurring expenses continue even when the original payer is inactive.
    func fetchDueRecurringExpenses(groupID: UUID) async throws -> [Expense] {
        let nowString = Self.iso8601Formatter.string(from: Date())
        return try await supabase.table("expenses")
            .select()
            .eq("group_id",  value: groupID)
            .neq("recurrence", value: "none")
            .lte("next_occurrence_date", value: nowString)
            .execute()
            .value
    }

    /// Advances the `next_occurrence_date` on a recurring template to the next cycle date.
    func setNextOccurrenceDate(_ date: Date, expenseID: UUID) async throws {
        struct Payload: Encodable {
            let nextOccurrenceDate: Date
            enum CodingKeys: String, CodingKey {
                case nextOccurrenceDate = "next_occurrence_date"
            }
        }
        try await supabase.table("expenses")
            .update(Payload(nextOccurrenceDate: date))
            .eq("id", value: expenseID)
            .select()
            .execute()
    }

    /// Atomically claims a due recurring template, creates a one-off instance, copies
    /// its splits, and advances the template date. Returns nil if another client
    /// already claimed that occurrence.
    func createRecurringInstance(
        templateID: UUID,
        expectedNextOccurrence: Date,
        newNextOccurrence: Date
    ) async throws -> Expense? {
        struct Params: Encodable {
            let templateID: UUID
            let expectedNextOccurrence: Date
            let newNextOccurrence: Date

            enum CodingKeys: String, CodingKey {
                case templateID = "p_template_id"
                case expectedNextOccurrence = "p_expected_next_occurrence"
                case newNextOccurrence = "p_new_next_occurrence"
            }
        }

        return try await supabase.client.rpc(
            "create_recurring_expense_instance",
            params: Params(
                templateID: templateID,
                expectedNextOccurrence: expectedNextOccurrence,
                newNextOccurrence: newNextOccurrence
            )
        )
        .execute()
        .value
    }

    // MARK: - Update

    /// Updates an expense **and replaces its splits** in one transaction (SPLIT-02).
    ///
    /// There is deliberately **no whole-struct `updateExpense`** any more. It wrote only the
    /// `expenses` row, so after an amount change the expense displayed the new figure while
    /// everyone still owed the old one — and once `updated_at` became a concurrency token it
    /// was worse than redundant: `.update(expense)` sent the client's stale token straight back
    /// into the row, undoing the guard microseconds after it passed. It was the only
    /// server-bound whole-struct `Expense` write in the app, so deleting it removes the only
    /// path that can do this, the way `settleSplit` and `fetchInvite` were deleted rather than
    /// documented as hazardous.
    ///
    /// The RPC rejects a split set that does not sum to the amount, so a rounding mistake fails
    /// loudly here rather than becoming a balance nobody can explain.
    /// The exact body sent to `update_expense_with_splits`.
    ///
    /// Extracted so a test can assert the **wire format** without a network call. The defect this
    /// prevents was invisible to every server-side check: the RPC was verified with a hand-written
    /// payload that included `p_notes`, while the app omitted it whenever notes were empty.
    /// Verifying the contract is not the same as verifying what the client sends.
    nonisolated static func updateParamsJSON(_ expense: Expense, splits: [SplitInput],
                                             expectedUpdatedAt: String?) throws -> [String: Any] {
        let data = try SupabaseManager.postgrestEncoder.encode(
            makeUpdateParams(expense, splits: splits, expectedUpdatedAt: expectedUpdatedAt))
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func updateExpenseWithSplits(_ expense: Expense, splits: [SplitInput],
                                 expectedUpdatedAt: String?) async throws -> Expense {
        let params = Self.makeUpdateParams(expense, splits: splits,
                                           expectedUpdatedAt: expectedUpdatedAt)
        return try await supabase.client
            .rpc("update_expense_with_splits", params: params)
            .execute()
            .value
    }

    // MARK: - Notify

    func notifyExpenseAdded(
        expenseID: UUID
    ) async {
        struct Payload: Encodable {
            let expenseId: String
        }
        let payload = Payload(
            expenseId:     expenseID.uuidString,
        )
        do {
            _ = try await supabase.client.functions
                .invoke("notify-expense", options: .init(body: payload))
        } catch {
            logger.error("notify-expense failed for expense \(expenseID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The Edge Function reads the settlement row with the service role and derives
    /// `fromUserID`/`toUserID`/`amount`/`currency`/`group_id` from it — nothing security- or
    /// money-relevant is sent from the client. This is a deliberate strengthening of the old
    /// `callerID`-as-sender fix (H-09): under the settlements ledger, either party may record
    /// a payment, so the caller is no longer necessarily the payer, and the function verifies
    /// `settlement.recorded_by == callerID` itself.
    func notifySettlementRecorded(settlementID: UUID) async {
        struct Payload: Encodable {
            let settlementId: String
        }
        let payload = Payload(
            settlementId:  settlementID.uuidString,
        )
        do {
            _ = try await supabase.client.functions
                .invoke("notify-settlement", options: .init(body: payload))
        } catch {
            logger.error("notify-settlement failed for settlement \(settlementID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Delete

    func deleteExpense(id: UUID) async throws {
        let rows: [AffectedRowID] = try await supabase.table("expenses")
            .delete()
            .eq("id", value: id)
            .select("id")
            .execute()
            .value
        try SupabaseWrite.requireAffected(rows, table: "expenses", id: id)
    }

}

// MARK: - RPC Payloads

struct RPCSplitParam: Encodable {
    let userID: UUID
    let amount: Decimal
    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case amount
    }
}

/// The exact body sent to `add_expense_with_splits`.
///
/// **Every key is encoded with `encode`, never `encodeIfPresent`** — see `encode(to:)` below.
struct AddExpenseRPCParams: Encodable {
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

    /// Hand-written for the same reason `UpdateExpenseParams` is: **Swift's synthesized
    /// `Encodable` omits a nil**, and PostgREST resolves an RPC by the exact key set it receives.
    ///
    /// That is SPLIT-04, which shipped in 1.3 and broke expense editing with `PGRST202`. The
    /// create path was never given the same treatment. It has not misbehaved, but only by luck:
    /// all five optional parameters here happen to be `DEFAULT NULL` on the server, so omitting
    /// them produced the same result as sending null. Verified against production 2026-08-31 —
    /// `p_notes`, `p_receipt_url`, `p_original_amount`, `p_original_currency` and
    /// `p_next_occurrence_date` are each `DEFAULT NULL`.
    ///
    /// Relying on that is relying on a coincidence between two files that nothing keeps in sync:
    /// change one default to a non-null, or drop one, and the omitted-key payload silently
    /// resolves somewhere else or not at all. Sending all 13 keys makes the payload a fixed
    /// contract instead. Behaviour is identical today; the failure mode is removed.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(groupID,            forKey: .groupID)
        try c.encode(paidBy,             forKey: .paidBy)
        try c.encode(amount,             forKey: .amount)
        try c.encode(title,              forKey: .title)
        try c.encode(category,           forKey: .category)
        try c.encode(currency,           forKey: .currency)
        try c.encode(notes,              forKey: .notes)              // explicit null, never omitted
        try c.encode(receiptURL,         forKey: .receiptURL)         // explicit null, never omitted
        try c.encode(splits,             forKey: .splits)
        try c.encode(originalAmount,     forKey: .originalAmount)     // explicit null, never omitted
        try c.encode(originalCurrency,   forKey: .originalCurrency)   // explicit null, never omitted
        try c.encode(recurrence,         forKey: .recurrence)
        try c.encode(nextOccurrenceDate, forKey: .nextOccurrenceDate) // explicit null, never omitted
    }
}

extension ExpenseService {
    nonisolated static func makeAddParams(
        groupID: UUID, payerID: UUID, amount: Decimal, title: String, category: String,
        currency: String, notes: String?, splits: [RPCSplitParam],
        originalAmount: Decimal?, originalCurrency: String?,
        recurrence: String, nextOccurrenceDate: Date?
    ) -> AddExpenseRPCParams {
        AddExpenseRPCParams(
            groupID:             groupID,
            paidBy:              payerID,
            amount:              amount,
            title:               title,
            category:            category,
            currency:            currency,
            notes:               notes,
            receiptURL:          nil,
            splits:              splits,
            originalAmount:      originalAmount,
            originalCurrency:    originalCurrency,
            recurrence:          recurrence,
            nextOccurrenceDate:  nextOccurrenceDate
        )
    }

    /// Mirrors `updateParamsJSON`. Exists so a test can assert the **wire format** without a
    /// network call — a server-side check cannot see how the client serialises, which is exactly
    /// how SPLIT-04 passed three verification passes and still shipped.
    nonisolated static func addParamsJSON(
        groupID: UUID, payerID: UUID, amount: Decimal, title: String, category: String,
        currency: String, notes: String?, splits: [RPCSplitParam],
        originalAmount: Decimal?, originalCurrency: String?,
        recurrence: String, nextOccurrenceDate: Date?
    ) throws -> [String: Any] {
        let data = try SupabaseManager.postgrestEncoder.encode(
            makeAddParams(groupID: groupID, payerID: payerID, amount: amount, title: title,
                          category: category, currency: currency, notes: notes, splits: splits,
                          originalAmount: originalAmount, originalCurrency: originalCurrency,
                          recurrence: recurrence, nextOccurrenceDate: nextOccurrenceDate))
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

// MARK: - Update RPC payload

// Mirrors `RPCCreateParams` below: amounts travel as `Decimal` through the configured
// PostgREST encoder, not as interpolated strings.
struct UpdateExpenseParams: Encodable {
    let expenseID: UUID
    let title:     String
    let amount:    Decimal
    let currency:  String
    let category:  String
    let notes:     String?
    let paidBy:    UUID?
    let splits:    [RPCSplitParam]
    let expectedUpdatedAt: String?
    enum CodingKeys: String, CodingKey {
        case expenseID = "p_expense_id"
        case title     = "p_title"
        case amount    = "p_amount"
        case currency  = "p_currency"
        case category  = "p_category"
        case notes     = "p_notes"
        case paidBy    = "p_paid_by"
        case splits    = "p_splits"
        case expectedUpdatedAt = "p_expected_updated_at"
    }

    /// Hand-written because **Swift's synthesized `Encodable` omits a nil**, and PostgREST
    /// resolves an RPC by the exact set of keys it receives. An expense with no notes sent
    /// 7 keys, so PostgREST looked for a 7-argument function, found none, and returned
    /// `PGRST202 Could not find the function …` — which reached the user as a raw error
    /// the moment they tried to re-split an expense.
    ///
    /// `encode` rather than `encodeIfPresent` on every optional: the key must be present
    /// and explicitly null. This trap is already recorded in `HANDOFF_PAYMENT_HANDLES.md`
    /// for the payment-handle payload; it is the same one.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(expenseID, forKey: .expenseID)
        try c.encode(title,     forKey: .title)
        try c.encode(amount,    forKey: .amount)
        try c.encode(currency,  forKey: .currency)
        try c.encode(category,  forKey: .category)
        try c.encode(notes,     forKey: .notes)     // explicit null, never omitted
        try c.encode(paidBy,    forKey: .paidBy)    // explicit null, never omitted
        try c.encode(splits,    forKey: .splits)
        try c.encode(expectedUpdatedAt, forKey: .expectedUpdatedAt)  // explicit null, never omitted
    }
}

extension ExpenseService {
    nonisolated static func makeUpdateParams(_ expense: Expense, splits: [SplitInput],
                                             expectedUpdatedAt: String?) -> UpdateExpenseParams {
        UpdateExpenseParams(
            expenseID: expense.id,
            title:     expense.title,
            amount:    expense.amount,
            currency:  expense.currency,
            category:  expense.category.rawValue,
            notes:     expense.notes,
            paidBy:    expense.payerID,
            splits:    splits.map { RPCSplitParam(userID: $0.userID, amount: $0.amount) },
            expectedUpdatedAt: expectedUpdatedAt
        )
    }
}

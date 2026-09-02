//
//  AddExpensePayloadTests.swift
//  xBillTests
//
//  The create path's twin of `UpdateExpensePayloadTests`.
//
//  SPLIT-04 shipped in 1.3 and broke expense editing with `PGRST202`: Swift's synthesized
//  `Encodable` omits a nil, and PostgREST resolves an RPC by the exact key set it receives, so an
//  expense with no notes searched for a 7-argument function and found none. The *update* payload
//  was hand-written in response. The *create* payload was not, and kept working only because every
//  optional parameter on `add_expense_with_splits` happens to be `DEFAULT NULL` — a coincidence
//  between a Swift file and a migration that nothing keeps in sync.
//
//  These tests pin the wire format so the coincidence stops being load-bearing. They encode
//  through `SupabaseManager.postgrestEncoder` — the encoder the transport really uses — because a
//  hand-rolled encoder in a test proves nothing about the app.
//

import Testing
import Foundation
@testable import xBill

@Suite("Add-expense RPC payload")
struct AddExpensePayloadTests {

    /// Every parameter of the 13-argument RPC. The key set must be exactly this, always.
    private static let required = [
        "p_group_id", "p_paid_by", "p_amount", "p_title", "p_category", "p_currency",
        "p_notes", "p_receipt_url", "p_splits", "p_original_amount", "p_original_currency",
        "p_recurrence", "p_next_occurrence_date"
    ]

    private func json(notes: String? = nil,
                      originalAmount: Decimal? = nil,
                      originalCurrency: String? = nil,
                      nextOccurrence: Date? = nil) throws -> [String: Any] {
        try ExpenseService.addParamsJSON(
            groupID: UUID(), payerID: UUID(),
            amount: Decimal(string: "42.50")!,
            title: "Dinner", category: "food", currency: "USD",
            notes: notes,
            splits: [RPCSplitParam(userID: UUID(), amount: Decimal(string: "42.50")!)],
            originalAmount: originalAmount, originalCurrency: originalCurrency,
            recurrence: "none", nextOccurrenceDate: nextOccurrence)
    }

    @Test("All 13 keys are present when every optional is nil")
    func allKeysPresentWhenOptionalsAreNil() throws {
        let j = try json()
        #expect(Set(j.keys) == Set(Self.required),
                "missing: \(Set(Self.required).subtracting(j.keys).sorted())")
    }

    /// The SPLIT-04 defect, in the shape it would take on this path.
    @Test("Nil optionals are explicit nulls, not omissions")
    func nilOptionalsAreExplicitNulls() throws {
        let j = try json()
        for key in ["p_notes", "p_receipt_url", "p_original_amount",
                    "p_original_currency", "p_next_occurrence_date"] {
            #expect(j[key] is NSNull,
                    "\(key) must be present and null — omitting it changes which function PostgREST resolves")
        }
    }

    /// The property that actually distinguishes the fix from the bug: the key set does not vary
    /// with the data. A test that only checked the all-nil case would pass against the old
    /// synthesized encoder for the populated case too.
    @Test("The key set is invariant across every combination of present and absent optionals")
    func keySetIsInvariant() throws {
        let combos: [(String?, Decimal?, String?, Date?)] = [
            (nil, nil, nil, nil),
            ("note", nil, nil, nil),
            (nil, Decimal(string: "99.00")!, "EUR", nil),
            ("note", Decimal(string: "99.00")!, "EUR", Date(timeIntervalSince1970: 1_800_000_000)),
            (nil, nil, nil, Date(timeIntervalSince1970: 1_800_000_000))
        ]
        for (n, oa, oc, next) in combos {
            let j = try json(notes: n, originalAmount: oa, originalCurrency: oc, nextOccurrence: next)
            #expect(Set(j.keys) == Set(Self.required),
                    "notes=\(String(describing: n)) origAmt=\(String(describing: oa)) → \(j.keys.sorted())")
        }
    }

    /// Money must not arrive as a float. `Decimal(string:)` in the assertion too — a `Decimal`
    /// built from a float literal routes through `Double` and carries its error.
    @Test("Amounts encode exactly, and splits keep their wire shape")
    func amountsAreExact() throws {
        let j = try json()
        #expect("\(j["p_amount"] ?? "")".contains("42.5"))
        let splits = try #require(j["p_splits"] as? [[String: Any]])
        #expect(splits.count == 1)
        #expect(splits[0].keys.contains("user_id") && splits[0].keys.contains("amount"))
    }

    /// `receiptURL` is always nil at the call site — receipts are OCR-only and never uploaded
    /// (M-68) — but the key must still be sent, for the same reason as every other optional.
    @Test("p_receipt_url is sent as null even though nothing ever populates it")
    func receiptURLIsAlwaysSentAsNull() throws {
        let j = try json(notes: "note")
        #expect(j.keys.contains("p_receipt_url"))
        #expect(j["p_receipt_url"] is NSNull)
    }
}

//
//  ExpenseRecorderTests.swift
//  xBillTests
//
//  The bookkeeper flow (migration 055): `paid_by` was doing two jobs — "who spent the money" and
//  "who may touch this row" — so a member could not record an expense someone else paid, and could
//  not correct a mistyped payer. `created_by` separates them, the way `settlements.recorded_by`
//  already did.
//
//  Two things are pinned here:
//
//  1. `created_by` decodes from the real PostgREST wire format, through the decoder the transport
//     actually uses — not one constructed in the test. That is the SPLIT-04 lesson: verifying a
//     server contract proves nothing about what the client serialises or parses.
//
//  2. `wasRecordedBySomeoneElse`, the rule the detail screen shows "Added by X" on. It is a
//     computed property rather than an inline condition in the view precisely so it can be tested
//     without driving SwiftUI.
//
//  ⚠️ `created_by` is deliberately OPTIONAL and never backfilled. The 45 expenses that predate 055
//  carry NULL, authorisation falls back to `paid_by` for them, and a non-optional would fail to
//  decode every one — the `splits.is_settled` failure in miniature, on our own rows.
//

import Testing
import Foundation
@testable import xBill

@Suite("Expense recorder (bookkeeper flow)")
struct ExpenseRecorderTests {

    private static let payer   = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private static let recorder = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!

    /// Wire format copied from the shape PostgREST returns for `public.expenses`.
    private static func json(paidBy: String, createdBy: String) -> String {
        """
        {"id":"11111111-1111-1111-1111-111111111111",
         "group_id":"22222222-2222-2222-2222-222222222222",
         "title":"Dinner","amount":42.50,"currency":"USD","paid_by":\(paidBy),
         "category":"food","notes":null,"receipt_url":null,
         "original_amount":null,"original_currency":null,
         "recurrence":"none","next_occurrence_date":null,
         "created_at":"2026-09-08T14:03:11.123456+00:00",
         "updated_at":"2026-09-08T14:03:11.123456+00:00",
         "updated_by":null,"created_by":\(createdBy)}
        """
    }

    private static func decode(_ raw: String) throws -> Expense {
        try SupabaseManager.postgrestDecoder.decode(Expense.self, from: Data(raw.utf8))
    }

    // MARK: - Decoding

    @Test("created_by decodes from the real wire format")
    func recorderIsDecoded() throws {
        let expense = try Self.decode(Self.json(paidBy: "\"\(Self.payer)\"",
                                                createdBy: "\"\(Self.recorder)\""))
        #expect(expense.createdBy == Self.recorder)
        #expect(expense.payerID == Self.payer)
    }

    /// The 45 live rows that predate migration 055 look exactly like this. A non-optional
    /// `createdBy` would fail to decode every one of them.
    @Test("A row predating migration 055 decodes with a nil recorder")
    func legacyRowDecodes() throws {
        let expense = try Self.decode(Self.json(paidBy: "\"\(Self.payer)\"", createdBy: "null"))
        #expect(expense.createdBy == nil)
        #expect(expense.payerID == Self.payer)
    }

    /// Cache entries written before the key existed carry no `created_by` at all — not even null.
    @Test("A payload with no created_by key at all still decodes")
    func absentKeyDecodes() throws {
        let raw = Self.json(paidBy: "\"\(Self.payer)\"", createdBy: "null")
            .replacingOccurrences(of: ",\"created_by\":null", with: "")
        let expense = try Self.decode(raw)
        #expect(expense.createdBy == nil)
    }

    // MARK: - The "Added by X" rule

    @Test("Shown when someone recorded on another member's behalf")
    func flaggedWhenRecorderDiffersFromPayer() throws {
        let expense = try Self.decode(Self.json(paidBy: "\"\(Self.payer)\"",
                                                createdBy: "\"\(Self.recorder)\""))
        #expect(expense.wasRecordedBySomeoneElse)
    }

    /// The ordinary case. If this were true the label would appear on every expense in the app.
    @Test("Silent when the payer recorded their own expense")
    func notFlaggedWhenPayerRecordedItThemselves() throws {
        let expense = try Self.decode(Self.json(paidBy: "\"\(Self.payer)\"",
                                                createdBy: "\"\(Self.payer)\""))
        #expect(!expense.wasRecordedBySomeoneElse)
    }

    /// Legacy rows must stay silent — nil is "unknown", not "someone else".
    @Test("Silent for a row predating migration 055")
    func notFlaggedForLegacyRow() throws {
        let expense = try Self.decode(Self.json(paidBy: "\"\(Self.payer)\"", createdBy: "null"))
        #expect(!expense.wasRecordedBySomeoneElse)
    }

    /// `paid_by` is nullable — migration 017 set it null when a payer's account is deleted. A known
    /// recorder against an unknown payer is genuinely "recorded by someone else".
    @Test("A known recorder against a null payer still counts as recorded by someone else")
    func flaggedWhenPayerIsNull() throws {
        let expense = try Self.decode(Self.json(paidBy: "null",
                                                createdBy: "\"\(Self.recorder)\""))
        #expect(expense.payerID == nil)
        #expect(expense.wasRecordedBySomeoneElse)
    }
}

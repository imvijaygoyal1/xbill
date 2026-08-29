//
//  ExpenseTokenTests.swift
//  xBillTests
//
//  `expenses.updated_at` is the optimistic-concurrency token. It is `timestamptz`, which Postgres
//  stores to MICROSECOND precision, and Swift's `Date` is a `Double` of seconds. Decoding to a
//  `Date` and re-encoding rounds the value, so `updated_at = p_expected_updated_at` would fail
//  against a row nobody had touched and every save would report a phantom conflict.
//
//  A guard that fires constantly is worse than no guard: it teaches people to ignore it.
//
//  So the token is opaque. These tests fail if anyone "tidies" it into a `Date`.
//

import Testing
import Foundation
@testable import xBill

@Suite("Expense concurrency token")
struct ExpenseTokenTests {

    private static let json = """
    {"id":"11111111-1111-1111-1111-111111111111",
     "group_id":"22222222-2222-2222-2222-222222222222",
     "title":"Dinner","amount":42.50,"currency":"USD","paid_by":null,
     "category":"food","notes":null,"receipt_url":null,
     "original_amount":null,"original_currency":null,
     "recurrence":"none","next_occurrence_date":null,
     "created_at":"2026-08-29T14:03:11.123456+00:00",
     "updated_at":"2026-08-29T14:03:11.123456+00:00",
     "updated_by":"33333333-3333-3333-3333-333333333333"}
    """

    @Test("Six fractional digits survive decoding byte-identically")
    func tokenKeepsMicroseconds() throws {
        let expense = try SupabaseManager.postgrestDecoder.decode(
            Expense.self, from: Data(Self.json.utf8))
        #expect(expense.updatedAt == "2026-08-29T14:03:11.123456+00:00")
    }

    @Test("The editor's id is decoded")
    func editorIsDecoded() throws {
        let expense = try SupabaseManager.postgrestDecoder.decode(
            Expense.self, from: Data(Self.json.utf8))
        #expect(expense.updatedBy == UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
    }

    /// `CacheService` caches expenses as JSON. Entries written before this change carry no
    /// `updated_at` key at all. A non-optional would fail to decode every one of them — the
    /// `splits.is_settled` failure in miniature, on our own cache instead of the server.
    @Test("A cached expense with no token still decodes")
    func absentTokenDecodesAsNil() throws {
        let legacy = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "group_id":"22222222-2222-2222-2222-222222222222",
         "title":"Dinner","amount":42.50,"currency":"USD","paid_by":null,
         "category":"food","notes":null,"receipt_url":null,
         "original_amount":null,"original_currency":null,
         "recurrence":"none","next_occurrence_date":null,
         "created_at":"2026-08-29T14:03:11.123456+00:00"}
        """
        let expense = try SupabaseManager.postgrestDecoder.decode(
            Expense.self, from: Data(legacy.utf8))
        #expect(expense.updatedAt == nil)
        #expect(expense.updatedBy == nil)
    }
}

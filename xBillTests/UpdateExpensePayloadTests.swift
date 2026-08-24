//
//  UpdateExpensePayloadTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  SPLIT-04. `update_expense_with_splits` was verified against production with a hand-written
//  payload containing `"p_notes": null`, and it passed. The app omitted that key entirely whenever
//  an expense had no notes, because **Swift's synthesized `Encodable` omits a nil** — and PostgREST
//  resolves an RPC by the exact set of keys it receives. Seven keys meant it searched for a
//  seven-argument function, found none, and answered:
//
//      PGRST202  Could not find the function public.update_expense_with_splits(p_amount, …)
//
//  which reached the user as a raw error the moment they tried to re-split an expense.
//
//  **Verifying the server contract is not verifying what the client sends.** These assert the
//  actual wire payload, encoded with the encoder PostgREST really uses.
//

import Testing
import Foundation
@testable import xBill

@Suite("Update-expense RPC payload")
struct UpdateExpensePayloadTests {

    private func expense(notes: String?, payer: UUID?) -> Expense {
        Expense(id: UUID(), groupID: UUID(), title: "Dinner",
                amount: Decimal(string: "42.50")!, currency: "USD",
                payerID: payer, category: .food, notes: notes, receiptURL: nil,
                originalAmount: nil, originalCurrency: nil, recurrence: .none,
                nextOccurrenceDate: nil, createdAt: Date())
    }
    private func input(_ amount: String) -> SplitInput {
        var i = SplitInput(userID: UUID(), displayName: "A")
        i.amount = Decimal(string: amount)!
        return i
    }
    private static let required = ["p_expense_id", "p_title", "p_amount", "p_currency",
                                   "p_category", "p_notes", "p_paid_by", "p_splits"]

    /// The defect, exactly: no notes must still send `p_notes`.
    @Test("A nil note is sent as an explicit null, not omitted")
    func nilNoteIsStillSent() throws {
        let json = try ExpenseService.updateParamsJSON(
            expense(notes: nil, payer: UUID()), splits: [input("42.50")])
        #expect(json["p_notes"] is NSNull,
                "p_notes must be present and null — omitting it makes PostgREST search for a 7-arg function")
        for key in Self.required {
            #expect(json.keys.contains(key), "missing \(key); PostgREST resolves by the exact key set")
        }
    }

    /// The same trap on the other optional.
    @Test("A nil payer is sent as an explicit null")
    func nilPayerIsStillSent() throws {
        let json = try ExpenseService.updateParamsJSON(
            expense(notes: "x", payer: nil), splits: [input("42.50")])
        #expect(json["p_paid_by"] is NSNull)
        #expect(json.keys.count == Self.required.count)
    }

    /// Every combination of the two optionals sends exactly eight keys.
    @Test("The key set is identical whatever is nil")
    func keySetIsInvariant() throws {
        for (notes, payer) in [(nil, nil), ("n", nil), (nil, UUID()), ("n", UUID())] as [(String?, UUID?)] {
            let json = try ExpenseService.updateParamsJSON(
                expense(notes: notes, payer: payer), splits: [input("42.50")])
            #expect(Set(json.keys) == Set(Self.required),
                    "notes=\(String(describing: notes)) payer=\(String(describing: payer)) → \(json.keys.sorted())")
        }
    }

    /// Money must not become a float on the wire.
    @Test("Amounts encode without float error")
    func amountsAreExact() throws {
        let json = try ExpenseService.updateParamsJSON(
            expense(notes: nil, payer: UUID()), splits: [input("42.50")])
        #expect("\(json["p_amount"] ?? "")".contains("42.5"))
        let splits = try #require(json["p_splits"] as? [[String: Any]])
        #expect(splits.count == 1)
        #expect(splits[0].keys.contains("user_id") && splits[0].keys.contains("amount"))
    }
}

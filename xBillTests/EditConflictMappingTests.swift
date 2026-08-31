//
//  EditConflictMappingTests.swift
//  xBillTests
//
//  The RPC raises the SAME text for a missing row and an RLS refusal. If a concurrency conflict
//  joined that bucket the client could only tell them apart by string-matching an error message.
//
//  This codebase has been burned by substring matching three times: `isNotFoundError` matched a
//  bare "406", the receipt parser's `credit` matched "CREDIT CARD PURCHASE", and `table` matched
//  "Vegetable". So a conflict carries its own SQLSTATE and is matched exactly.
//

import Testing
import Foundation
import Supabase
@testable import xBill

@Suite("Edit-conflict error mapping")
struct EditConflictMappingTests {

    private func pgError(code: String) -> PostgrestError {
        PostgrestError(detail: nil, hint: nil, code: code,
                       message: "This expense was changed by someone else")
    }

    @Test("XB409 is recognised as an edit conflict")
    func exactCodeMatches() {
        #expect(AppError.isEditConflict(pgError(code: "XB409")))
    }

    /// The whole point of a structured code: a neighbouring one must NOT match.
    @Test("A different code is not a conflict")
    func neighbouringCodeDoesNotMatch() {
        #expect(!AppError.isEditConflict(pgError(code: "XB410")))
        #expect(!AppError.isEditConflict(pgError(code: "PGRST202")))
        #expect(!AppError.isEditConflict(pgError(code: "42501")))
    }

    /// Matching must be on the code, never the message — otherwise any error whose text happens
    /// to contain these words becomes a conflict.
    @Test("The message alone does not make a conflict")
    func messageAloneIsNotAConflict() {
        struct Plain: Error, LocalizedError {
            var errorDescription: String? { "This expense was changed by someone else" }
        }
        #expect(!AppError.isEditConflict(Plain()))
    }
}

//
//  AffectedRowsTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  REV-06. A PostgREST write that matches no row returns HTTP 200 with an empty body, so
//  every `update`/`delete` without an affected-row check reports success when RLS denied it
//  or the row was already gone. `NOTIF-04` was that bug in the notifications table; this
//  covers the shared helper the rest of the services now use.
//

import Foundation
import Testing
@testable import xBill

@Suite("Affected-row acknowledgement")
struct AffectedRowsTests {

    @Test("A zero-row write is reported, naming the table and id")
    func zeroRowsThrows() {
        let id = UUID()
        #expect(throws: SupabaseWriteError.noRowsAffected(table: "expenses", id: id)) {
            try SupabaseWrite.requireAffected([], table: "expenses", id: id)
        }
    }

    @Test("A single affected row is accepted")
    func oneRowSucceeds() throws {
        let id = UUID()
        try SupabaseWrite.requireAffected([AffectedRowID(id: id)], table: "expenses", id: id)
    }

    @Test("Several affected rows are accepted")
    func manyRowsSucceed() throws {
        let id = UUID()
        try SupabaseWrite.requireAffected(
            [AffectedRowID(id: UUID()), AffectedRowID(id: UUID())],
            table: "friends",
            id: id
        )
    }

    /// Pins the wire shape: `return=representation` answers with a JSON array, which is what
    /// makes the affected-row count observable. `.single()` only swaps an Accept header and
    /// turns a zero-row match into an opaque "cannot coerce" error.
    @Test("The response decodes as an array of ids")
    func responseDecodesAsArray() throws {
        let id = UUID()
        let rows = try JSONDecoder().decode(
            [AffectedRowID].self,
            from: Data(#"[{"id":"\#(id.uuidString)"}]"#.utf8)
        )

        #expect(rows == [AffectedRowID(id: id)])
        try SupabaseWrite.requireAffected(rows, table: "expenses", id: id)
    }

    @Test("An empty array is the wire shape of a zero-row match")
    func emptyArrayIsZeroRows() throws {
        let rows = try JSONDecoder().decode([AffectedRowID].self, from: Data("[]".utf8))
        #expect(rows.isEmpty)
    }

    @Test("The error message is user-facing, not a raw PostgREST string")
    func errorMessageIsReadable() {
        let message = SupabaseWriteError.noRowsAffected(table: "expenses", id: UUID())
            .errorDescription ?? ""
        #expect(message.contains("could not be"))
        #expect(!message.contains("coerce"))
    }
}

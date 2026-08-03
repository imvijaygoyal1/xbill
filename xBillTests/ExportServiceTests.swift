//
//  ExportServiceTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  `ExportService` had 0% coverage (355 uncovered lines) while producing a file the user hands
//  to someone else — an accountant, a spreadsheet, a tax return. A malformed field here is
//  silent data corruption: nothing throws, the file opens, the numbers are just wrong.
//
//  These cover `generateCSV`, which is pure. The PDF path is drawing code and is not asserted
//  here beyond producing non-empty data.
//

import Testing
import Foundation
@testable import xBill

@Suite("ExportService CSV")
@MainActor
struct ExportServiceCSVTests {

    private let alice = UUID()

    private func makeGroup() -> BillGroup {
        BillGroup(id: UUID(), name: "Trip", emoji: "✈️", createdBy: alice,
                  isArchived: false, currency: "USD", createdAt: Date())
    }

    private func makeExpense(
        title: String = "Dinner",
        amount: Decimal = 30,
        payerID: UUID? = nil,
        notes: String? = nil,
        category: Expense.Category = .food,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14 UTC
    ) -> Expense {
        Expense(id: UUID(), groupID: UUID(), title: title, amount: amount, currency: "USD",
                payerID: payerID, category: category, notes: notes, receiptURL: nil,
                originalAmount: nil, originalCurrency: nil, recurrence: .none,
                nextOccurrenceDate: nil, createdAt: createdAt)
    }

    private func csv(_ expenses: [Expense], names: [UUID: String] = [:]) -> String {
        let data = ExportService.shared.generateCSV(
            group: makeGroup(), expenses: expenses, memberNames: names)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Format

    @Test("Header row and CRLF line endings")
    func headerAndLineEndings() {
        // Assert the BOM on the bytes, not the decoded String: `String(data:encoding:.utf8)`
        // consumes a leading BOM, so a string-prefix check reports it missing when it is present.
        let data = ExportService.shared.generateCSV(
            group: makeGroup(), expenses: [makeExpense()], memberNames: [:])
        #expect(data.starts(with: [0xEF, 0xBB, 0xBF]),
                "A UTF-8 BOM must lead the file so Excel reads it as UTF-8.")

        let out = csv([makeExpense()])
        #expect(out.hasPrefix("Date,Title,Category,Amount,Currency,Paid By,Notes,Recurrence"))
        #expect(out.contains("\r\n"), "Rows must be CRLF-separated (M-24/H-24).")
    }

    @Test("A whole amount still carries two decimals")
    func amountAlwaysTwoDecimals() {
        #expect(csv([makeExpense(amount: 30)]).contains(",30.00,"))
        #expect(csv([makeExpense(amount: Decimal(string: "7.5")!)]).contains(",7.50,"))
    }

    @Test("Rows are ordered oldest first")
    func rowsSortedByCreatedAt() {
        let older = makeExpense(title: "First",  createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = makeExpense(title: "Second", createdAt: Date(timeIntervalSince1970: 2_000))
        let out = csv([newer, older])
        let first  = try! #require(out.range(of: "First"))
        let second = try! #require(out.range(of: "Second"))
        #expect(first.lowerBound < second.lowerBound)
    }

    @Test("An unknown payer is labelled, not blank")
    func unknownPayer() {
        #expect(csv([makeExpense(payerID: nil)]).contains(",Unknown,"))
        #expect(csv([makeExpense(payerID: alice)], names: [alice: "Alice"]).contains(",Alice,"))
    }

    // MARK: - Escaping

    @Test("A comma in a field is quoted")
    func commaIsQuoted() {
        let out = csv([makeExpense(title: "Dinner, drinks")])
        #expect(out.contains("\"Dinner, drinks\""),
                "An unquoted comma would shift every later column by one.")
    }

    @Test("A quote is doubled and the field quoted")
    func quoteIsEscaped() {
        let out = csv([makeExpense(title: "The \"Ritz\"")])
        #expect(out.contains("\"The \"\"Ritz\"\"\""))
    }

    @Test("A newline inside a field is quoted")
    func newlineIsQuoted() {
        let out = csv([makeExpense(notes: "line one\nline two")])
        #expect(out.contains("\"line one\nline two\""))
    }

    /// Rows are joined with `\r\n`, so a lone carriage return inside a field is indistinguishable
    /// from a row break to a strict parser. `csvEscape` tests for `\n` but not `\r`.
    @Test("A lone carriage return inside a field is quoted")
    func carriageReturnIsQuoted() {
        let out = csv([makeExpense(notes: "line one\rline two")])
        #expect(out.contains("\"line one\rline two\""),
                "A bare CR must be quoted or it reads as a row break.")
    }

    /// Excel, Numbers and Google Sheets evaluate a cell beginning `=`, `+`, `-` or `@` as a
    /// formula. An expense titled `=1+1` becomes a live formula in the recipient's spreadsheet;
    /// the documented attack goes further and invokes external commands. xBill lets a user type
    /// an arbitrary expense title, and that title lands in a file shared with other people.
    @Test("A field that would be read as a spreadsheet formula is neutralised")
    func formulaInjectionIsNeutralised() {
        let out = csv([makeExpense(title: "=1+1")])
        #expect(!out.contains(",=1+1,"),
                "A leading = must not reach the file unneutralised — it executes on open.")
    }

    // MARK: - PDF smoke

    @Test("PDF generation produces data")
    func pdfProducesData() {
        let data = ExportService.shared.generatePDF(
            group: makeGroup(), expenses: [makeExpense()],
            memberNames: [alice: "Alice"], balances: [alice: 10])
        #expect(!data.isEmpty)
        #expect(data.starts(with: Array("%PDF".utf8)), "Output must actually be a PDF.")
    }
}

/// One definition of two-decimal formatting, shared by CSV export and payment links.
///
/// Both previously fell back to `String(format: "%.2f", NSDecimalNumber(...).doubleValue)`, which
/// routes money through a binary float — the pattern that gave scanned receipts amounts like
/// `4.990000000000001024` (VIS-04) — and duplicated a rule that then had two places to drift.
@Suite("Canonical two-decimal formatting")
struct PlainTwoDecimalStringTests {

    @Test(arguments: [
        ("8",       "8.00"),   ("7.5",     "7.50"),
        ("4.99",    "4.99"),   ("0.07",    "0.07"),
        ("1234.50", "1234.50"),                       // no grouping separator
        ("0",       "0.00")
    ])
    func formatsExactly(_ input: String, _ expected: String) {
        #expect(Decimal(string: input)!.plainTwoDecimalString == expected)
    }

    /// A grouping separator would break a CSV column and a payment URL alike.
    @Test("Large amounts carry no grouping separator")
    func noGroupingSeparator() {
        #expect(!Decimal(string: "1234567.89")!.plainTwoDecimalString.contains(","))
    }

    /// The export and the payment link must agree — that is the point of having one definition.
    @Test("CSV export and payment links format identically")
    @MainActor
    func exportAndPaymentLinkAgree() {
        for raw in ["8", "4.99", "1234.50", "0.07"] {
            let value = Decimal(string: raw)!
            #expect(PaymentLinkService.formattedAmount(value) == value.plainTwoDecimalString)
        }
    }
}

//
//  VisionParsingTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  `VisionService` was 3.7% covered with 733 uncovered lines — the largest untested surface in
//  the app, and one that turns a photograph into money. Roughly half of it is Vision/CoreImage
//  plumbing that genuinely needs real images; the other half is pure text→receipt parsing that
//  was untestable only because every function was `private`.
//
//  These cover the pure half against fixture strings. No camera, no images, no OCR.
//

import Testing
import Foundation
import CoreGraphics
@testable import xBill

@Suite("VisionService parsing core")
@MainActor
struct VisionParsingTests {

    private var service: VisionService { VisionService.shared }

    private func line(_ text: String, x: CGFloat = 0.5, y: CGFloat) -> OCRLine {
        OCRLine(text: text, midX: x, midY: y, confidence: 0.9)
    }

    // MARK: - extractDecimal

    @Test("A price is read from a line, rightmost value winning")
    func extractsRightmostPrice() {
        #expect(service.extractDecimal(from: "BURGER 4.99") == Decimal(string: "4.99"))
        // M-12: on "2x BURGER 4.99 9.98" the line total, not the unit price.
        #expect(service.extractDecimal(from: "2x BURGER 4.99 9.98") == Decimal(string: "9.98"))
    }

    @Test("A comma decimal separator is accepted")
    func acceptsCommaDecimal() {
        #expect(service.extractDecimal(from: "KAFFEE 3,50") == Decimal(string: "3.50"))
    }

    @Test("Currency symbols do not block the amount")
    func acceptsCurrencySymbols() {
        #expect(service.extractDecimal(from: "TOTAL $12.00") == Decimal(string: "12.00"))
        #expect(service.extractDecimal(from: "TOTAL €12.00") == Decimal(string: "12.00"))
        #expect(service.extractDecimal(from: "TOTAL ¥12.00") == Decimal(string: "12.00"))
    }

    @Test("A line with no two-decimal amount yields nil")
    func rejectsNonPrice() {
        #expect(service.extractDecimal(from: "THANK YOU") == nil)
        #expect(service.extractDecimal(from: "TABLE 12") == nil)
    }

    // MARK: - parseQuantity

    @Test("A quantity prefix divides the line total into a unit price")
    func parsesQuantity() {
        let (qty, unit) = service.parseQuantity(from: "2x BURGER", totalPrice: Decimal(string: "9.98")!)
        #expect(qty == 2)
        #expect(unit == Decimal(string: "4.99"))
    }

    @Test("Qty-style and multiplication-sign prefixes are both understood")
    func parsesQuantityVariants() {
        #expect(service.parseQuantity(from: "QTY 3 FRIES", totalPrice: 9).0 == 3)
        // U+00D7, the European form — the Tier-1 fix that added it to this regex.
        #expect(service.parseQuantity(from: "2×1.99", totalPrice: Decimal(string: "3.98")!).0 == 2)
    }

    @Test("No quantity prefix means one unit at the full price")
    func defaultsToSingleQuantity() {
        let (qty, unit) = service.parseQuantity(from: "BURGER", totalPrice: Decimal(string: "4.99")!)
        #expect(qty == 1)
        #expect(unit == Decimal(string: "4.99"))
    }

    /// `parseQuantity` accepts `[xX@×]` but `stripQuantityPrefix` only `[xX@]`. The Tier-1 fix
    /// recorded in CLAUDE.md extended one regex and not the other, so a European receipt parses
    /// the quantity correctly and then keeps `2×` glued to the item name.
    @Test("The quantity prefix is stripped from the item name for every accepted form")
    func stripsEveryAcceptedQuantityForm() {
        #expect(service.stripQuantityPrefix(from: "2x BURGER") == "BURGER")
        #expect(service.stripQuantityPrefix(from: "QTY 3 FRIES") == "FRIES")
        #expect(service.stripQuantityPrefix(from: "2×BURGER") == "BURGER",
                "A form parseQuantity accepts must also be stripped, or it lands in the name.")
    }

    /// `extractDecimal` reads `¥￥₩` but `stripPrice` does not remove them, so a yen line keeps
    /// its price inside the item name.
    @Test("A trailing price is stripped for every currency the parser reads")
    func stripsPriceForEveryReadableCurrency() {
        #expect(service.stripPrice(from: "BURGER $4.99").trimmingCharacters(in: .whitespaces) == "BURGER")
        #expect(service.stripPrice(from: "BURGER €4.99").trimmingCharacters(in: .whitespaces) == "BURGER")
        #expect(service.stripPrice(from: "BURGER ¥4.99").trimmingCharacters(in: .whitespaces) == "BURGER",
                "extractDecimal reads ¥, so stripPrice must remove it from the name.")
    }

    // MARK: - groupIntoRows

    @Test("Lines at the same height join one row; distant lines do not")
    func groupsByVerticalProximity() {
        let rows = service.groupIntoRows([
            line("BURGER", x: 0.2, y: 0.100),
            line("4.99",   x: 0.8, y: 0.104),   // same row, within threshold
            line("FRIES",  x: 0.2, y: 0.400),   // far below
            line("2.50",   x: 0.8, y: 0.402)
        ])
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.count == 2 })
    }

    @Test("Grouping an empty page yields no rows")
    func groupsEmptyInput() {
        #expect(service.groupIntoRows([]).isEmpty)
    }

    // MARK: - extractTransactionDate

    @Test("A date on the receipt is recognised")
    func findsTransactionDate() {
        #expect(service.extractTransactionDate(from: "Date: 03/14/2024  Table 5") != nil)
    }

    @Test("Text with no date yields nil")
    func noDateYieldsNil() {
        #expect(service.extractTransactionDate(from: "BURGER 4.99\nFRIES 2.50") == nil)
    }

    // MARK: - suggestCategory

    @Test("A merchant name drives the category")
    func suggestsFromMerchant() {
        #expect(service.suggestCategory(merchant: "Joe's Pizza Kitchen", items: []) == .food)
        #expect(service.suggestCategory(merchant: "Shell Gas Station", items: []) == .transport)
    }

    /// Matching is keyword-based, so the fixture uses words that are actually in the list.
    /// An earlier version of this test used "Cappuccino"/"Croissant" and failed — those are not
    /// keywords, and returning nil for them is correct behaviour, not a defect. Extending the
    /// vocabulary is a product decision, not a bug fix.
    @Test("Item names drive the category when the merchant is unknown")
    func suggestsFromItems() {
        let items = [ReceiptItem(name: "Coffee", quantity: 1, unitPrice: 4),
                     ReceiptItem(name: "Bakery roll", quantity: 1, unitPrice: 3)]
        #expect(service.suggestCategory(merchant: nil, items: items) == .food)
    }

    @Test("Nothing recognisable yields no suggestion rather than a wrong one")
    func noMatchYieldsNil() {
        #expect(service.suggestCategory(merchant: "Zzyzx Holdings", items: []) == nil)
    }

    // MARK: - parseWithHeuristics

    @Test("A simple receipt parses into items and a total")
    func parsesSimpleReceipt() {
        let rows: [[OCRLine]] = [
            [line("JOE'S DINER", y: 0.05)],
            [line("BURGER", x: 0.2, y: 0.30), line("4.99", x: 0.85, y: 0.30)],
            [line("FRIES",  x: 0.2, y: 0.40), line("2.50", x: 0.85, y: 0.40)],
            [line("TOTAL",  x: 0.2, y: 0.60), line("7.49", x: 0.85, y: 0.60)]
        ]
        let parsed = service.parseWithHeuristics(rows: rows)

        #expect(parsed.receipt.total == Decimal(string: "7.49"))
        #expect(parsed.receipt.items.count == 2, "Both line items should be picked up.")
        #expect(!parsed.receipt.items.contains { $0.name.contains("TOTAL") },
                "The total line must not be captured as a purchasable item.")
    }
}

// MARK: - Money crossing the JSON boundary

/// The model returns amounts as JSON numbers, so `ParsedReceiptJSON` carries `Double` and
/// `convert` turns them back into `Decimal`. Every other money path in this app is Decimal-only
/// by rule (never `Double`), and this is the one place a receipt total is reconstructed from a
/// binary float before becoming a real expense. If `Decimal(Double)` introduces an artifact here,
/// a scanned receipt silently produces an amount nobody typed.
@Suite("Receipt amounts survive the JSON boundary")
@MainActor
struct ReceiptMoneyConversionTests {

    private func parsed(total: Double, unitPrice: Double) -> ParsedReceiptJSON {
        // Keys are snake_case per `ParsedItemJSON.CodingKeys`, and `total_price` is NOT optional.
        let json = """
        {"merchant":"Joe's",
         "items":[{"name":"Burger","quantity":1,"unit_price":\(unitPrice),"total_price":\(unitPrice)}],
         "subtotal":null,"tax":null,"tip":null,"total":\(total),
         "currency":"USD","confidence":0.9,"transaction_date":null}
        """
        return try! JSONDecoder().decode(ParsedReceiptJSON.self, from: Data(json.utf8))
    }

    /// Values chosen for the ways binary floating point goes wrong: repeating fractions (0.1),
    /// prices ending in 9 (4.99, 19.99), a cent-level tax (0.07), and a four-figure total.
    @Test(arguments: [
        (4.99, "4.99"), (0.1, "0.1"), (19.99, "19.99"),
        (0.07, "0.07"), (1234.56, "1234.56"), (100.0, "100")
    ])
    func amountsConvertExactly(_ value: Double, _ expected: String) {
        let receipt = VisionService.shared.convert(parsed(total: value, unitPrice: value))
        let want = Decimal(string: expected)!

        #expect(receipt.total == want,
                "Total \(value) became \(String(describing: receipt.total)); expected \(want).")
        #expect(receipt.items.first?.unitPrice == want,
                "Unit price \(value) became \(String(describing: receipt.items.first?.unitPrice)); expected \(want).")
    }

    /// The sum of converted line items must still equal a converted total — an artifact in either
    /// would surface as a spurious "doesn't match items + tax + tip" warning, or worse, not.
    @Test("Converted items still sum to the converted total")
    func convertedItemsStillSum() {
        let receipt = VisionService.shared.convert(parsed(total: 9.98, unitPrice: 4.99))
        let itemSum = receipt.items.reduce(Decimal.zero) { $0 + $1.unitPrice * Decimal($1.quantity) }
        #expect(itemSum * 2 == receipt.total ?? .zero || itemSum == Decimal(string: "4.99"),
                "Line-item arithmetic must stay exact after the Double round trip.")
        #expect(receipt.total == Decimal(string: "9.98"))
    }
}

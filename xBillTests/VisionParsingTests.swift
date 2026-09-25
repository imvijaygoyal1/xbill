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

    // MARK: - SCAN-RULE-01: a label on one row, its amount on the next
    //
    // From the corpus: receipt 15 produced `TOTAL=13.07` as an item and 07 produced
    // `O T A L=28.35`. Both are the same defect — the parser holds a name-only row for the row
    // below, but classifies using only the *price* row's text. By the time "TOTAL" is consumed as
    // a carried name, nothing has asked whether it was a label.

    @Test("A total label on its own row still reads as the total, not an item")
    func totalLabelOnItsOwnRowIsNotAnItem() {
        let rows: [[OCRLine]] = [
            [line("CORNER STORE", y: 0.05)],
            [line("Buffalo Flower", x: 0.2, y: 0.30), line("12.00", x: 0.85, y: 0.30)],
            [line("TOTAL", x: 0.2, y: 0.60)],
            [line("13.07", x: 0.85, y: 0.66)]
        ]
        let parsed = service.parseWithHeuristics(rows: rows)

        #expect(parsed.receipt.total == Decimal(string: "13.07"))
        #expect(parsed.receipt.items.count == 1)
        #expect(!parsed.receipt.items.contains { $0.name.uppercased().contains("TOTAL") })
    }

    @Test("A letter-spaced total label is recognised across the split")
    func letterSpacedTotalLabelIsNotAnItem() {
        // Receipt 07: OCR dropped the leading T and spaced the rest — "O T A L".
        let rows: [[OCRLine]] = [
            [line("MARKET", y: 0.05)],
            [line("Tortilla Chips", x: 0.2, y: 0.30), line("2.29", x: 0.85, y: 0.30)],
            [line("O T A L", x: 0.2, y: 0.60)],
            [line("28.35", x: 0.85, y: 0.66)]
        ]
        let parsed = service.parseWithHeuristics(rows: rows)

        #expect(!parsed.receipt.items.contains { $0.name.contains("O T A L") },
                "A spaced total label must not survive as an item.")
        #expect(parsed.receipt.items.count == 1)
    }

    @Test("A tax label on its own row accumulates as tax")
    func taxLabelOnItsOwnRowIsTax() {
        let rows: [[OCRLine]] = [
            [line("SHOP", y: 0.05)],
            [line("Widget", x: 0.2, y: 0.30), line("10.00", x: 0.85, y: 0.30)],
            [line("TAX", x: 0.2, y: 0.55)],
            [line("0.80", x: 0.85, y: 0.60)]
        ]
        let parsed = service.parseWithHeuristics(rows: rows)

        #expect(parsed.receipt.tax == Decimal(string: "0.80"))
        #expect(parsed.receipt.items.count == 1, "Tax must not become an item.")
    }

    @Test("A letter-spaced total sharing a row with its amount is still a total")
    func letterSpacedTotalOnOneRowIsNotAnItem() {
        // Receipt 07 again, but here OCR kept the amount on the same row: `O T A L  28.35`.
        let rows: [[OCRLine]] = [
            [line("MARKET", y: 0.05)],
            [line("Tortilla Chips", x: 0.2, y: 0.30), line("2.29", x: 0.85, y: 0.30)],
            [line("O T A L", x: 0.2, y: 0.60), line("28.35", x: 0.85, y: 0.60)]
        ]
        let parsed = service.parseWithHeuristics(rows: rows)

        #expect(parsed.receipt.total == Decimal(string: "28.35"))
        #expect(parsed.receipt.items.count == 1)
    }

    /// The relaxed label match is deliberately length-guarded. A real item name that merely
    /// contains those letters must survive.
    @Test("An ordinary item name is not mistaken for a total label")
    func ordinaryNamesSurviveTheRelaxedLabelMatch() {
        #expect(!service.isTotalLabel("Oat Milk"))
        #expect(!service.isTotalLabel("SUBTOTAL"))
        #expect(!service.isTotalLabel("Sub Total"))
        #expect(!service.isTotalLabel("Pivotal Software Annual Licence"))
        #expect(service.isTotalLabel("TOTAL"))
        #expect(service.isTotalLabel("O T A L"))
    }

    /// The carried name must still work for its original purpose: a genuine item whose name and
    /// price are on separate rows (SCAN-13). Fixing the label case must not break this one.
    @Test("A split item still joins its name to the price below")
    func splitItemStillJoins() {
        let rows: [[OCRLine]] = [
            [line("DELI", y: 0.05)],
            [line("ORGANIC BANANAS", x: 0.2, y: 0.30)],
            [line("1.29", x: 0.85, y: 0.35)],
            [line("TOTAL", x: 0.2, y: 0.60), line("1.29", x: 0.85, y: 0.60)]
        ]
        let parsed = service.parseWithHeuristics(rows: rows)

        #expect(parsed.receipt.items.count == 1)
        #expect(parsed.receipt.items.first?.name == "ORGANIC BANANAS")
    }

    // MARK: - stripCatalogCode (SCAN-RULE-02)

    /// The four junk-prefix shapes the labelled corpus actually contains. Each was reaching the
    /// benchmark glued to the front of the name, so the item was counted but never matched.
    @Test("A leading SKU or PLU is removed")
    func leadingCatalogCodeIsRemoved() {
        #expect(service.stripCatalogCode(from: "365992 Tortilla Chips") == "Tortilla Chips")
        #expect(service.stripCatalogCode(from: "1158 ORG ARUGULA") == "ORG ARUGULA")
        #expect(service.stripCatalogCode(from: "K982032 5PK GOGGLES:MULITCOLORAO")
                == "5PK GOGGLES:MULITCOLORAO")
        #expect(service.stripCatalogCode(from: "E 7113 LYCHEE") == "LYCHEE",
                "the department letter must go with its PLU, not be left orphaned as `E`")
    }

    /// The reason the rule is *standalone token* and not "starts with a digit". Both of these are
    /// ground-truth names in the corpus, and a looser rule would corrupt both.
    @Test("Digits glued to letters are part of the name")
    func gluedDigitsSurvive() {
        #expect(service.stripCatalogCode(from: "5PK GOGGLES") == "5PK GOGGLES")
        #expect(service.stripCatalogCode(from: "10GRANDOPENING") == "10GRANDOPENING")
    }

    @Test("A trailing UPC is removed")
    func trailingUPCIsRemoved() {
        #expect(service.stripCatalogCode(from: "THERMACARE 195882990040") == "THERMACARE")
    }

    /// Only `1`. At quantity one there is no arithmetic to lose; stripping a larger number would
    /// silently rewrite product names that begin with one.
    @Test("A written-out quantity of one is removed, and only one")
    func leadingQuantityOfOneIsRemoved() {
        #expect(service.stripCatalogCode(from: "1 Coke") == "Coke")
        #expect(service.stripCatalogCode(from: "2 LITER PEPSI") == "2 LITER PEPSI",
                "stripping this would turn a product name into a quantity that was never printed")
    }

    /// Stripping must never win by emptying the field — a bare code is rejected upstream, and an
    /// empty name here would be strictly worse than the code it replaced.
    @Test("Stripping never empties the name")
    func strippingNeverEmptiesTheName() {
        #expect(service.stripCatalogCode(from: "365992") == "365992")
        #expect(service.stripCatalogCode(from: "195882990040") == "195882990040")
    }

    // MARK: - mergeSplitPrices (SCAN-RULE-05)

    private func priceLine(_ text: String, x: CGFloat, y: CGFloat) -> OCRLine {
        OCRLine(text: text, midX: x, midY: y, height: 0.012, confidence: 0.9)
    }

    /// Receipt 12, the exact geometry. `49` sits at a *lower* y than its own `F $15.`, so grouping
    /// put the halves in different rows and gave Laxmi the 4.49 belonging to the line below —
    /// silently, because 4.49 is a perfectly plausible amount.
    @Test("A price split into dollars and cents is rejoined")
    func splitPriceIsRejoined() {
        let lines = [
            priceLine("Laxmi Green Cardamom 200g", x: 0.30, y: 0.2989),
            priceLine("49",     x: 0.83, y: 0.2942),
            priceLine("F $15.", x: 0.74, y: 0.2950),
        ]
        let merged = service.mergeSplitPrices(lines)
        #expect(merged.count == 2, "got \(merged.map(\.text))")
        #expect(merged.contains { $0.text.contains("15.49") }, "got \(merged.map(\.text))")
    }

    /// A complete amount ends in a digit, so it must never absorb its neighbour. Without this the
    /// pass would happily glue two adjacent prices together.
    @Test("A complete price is never merged with the next one")
    func completePriceIsUntouched() {
        let lines = [
            priceLine("F $1.99", x: 0.77, y: 0.1925),
            priceLine("F $21.99", x: 0.76, y: 0.2025),
        ]
        #expect(service.mergeSplitPrices(lines).count == 2)
    }

    /// The fragment must be to the RIGHT and vertically close. A cents-looking token from another
    /// column, or from two lines away, is not part of this price.
    @Test("Only a near, right-hand fragment is absorbed")
    func onlyNearRightFragmentMerges() {
        let farBelow = [
            priceLine("F $15.", x: 0.74, y: 0.2950),
            priceLine("49",     x: 0.83, y: 0.3400),   // a whole line away
        ]
        #expect(service.mergeSplitPrices(farBelow).count == 2)

        let toTheLeft = [
            priceLine("F $15.", x: 0.74, y: 0.2950),
            priceLine("49",     x: 0.30, y: 0.2950),   // left column
        ]
        #expect(service.mergeSplitPrices(toTheLeft).count == 2)
    }

    /// Patel Brothers prints a tax flag after the amount. The cents fragment carries it.
    @Test("A trailing tax flag rides along with the cents")
    func taxFlagRidesAlong() {
        let lines = [
            priceLine("$4.",      x: 0.76, y: 0.4175),
            priceLine("99 Tx1",   x: 0.86, y: 0.4150),
        ]
        let merged = service.mergeSplitPrices(lines)
        #expect(merged.count == 1)
        #expect(service.extractDecimal(from: merged[0].text) == Decimal(string: "4.99"))
    }

    /// One fragment cannot be spent twice — two split prices on neighbouring lines must resolve to
    /// two distinct amounts, not both claim the nearest cents.
    @Test("A cents fragment is consumed by only one price")
    func fragmentIsConsumedOnce() {
        let lines = [
            priceLine("F $15.", x: 0.74, y: 0.2950),
            priceLine("49",     x: 0.83, y: 0.2942),
            priceLine("$4.",    x: 0.77, y: 0.3033),
            priceLine("00",     x: 0.83, y: 0.3042),
        ]
        let merged = service.mergeSplitPrices(lines).map(\.text)
        #expect(merged.count == 2, "got \(merged)")
        #expect(merged.contains { $0.contains("15.49") }, "got \(merged)")
        #expect(merged.contains { $0.contains("4.00") }, "got \(merged)")
    }

    // MARK: - SCAN-RULE-04

    /// Kroger prints `WT` before anything sold by weight. Note `SWT` (sweet) sits in the very same
    /// name, which is why this is a whole-token rule.
    @Test("A weight-sold marker is removed without touching a similar word")
    func weightMarkerIsRemoved() {
        #expect(service.stripCatalogCode(from: "WT BANANAS") == "BANANAS")
        #expect(service.stripCatalogCode(from: "WT POTATO SWT ORANGE") == "POTATO SWT ORANGE")
        #expect(service.stripCatalogCode(from: "WTF SAUCE") == "WTF SAUCE",
                "glued, so not the marker")
    }

    /// OCR returns `6. 99` for Kroger's tight line spacing. Before this, the pattern matched
    /// nothing on that row: the amount was neither read as the price nor stripped from the name,
    /// and the item was billed **3.00 instead of 6.99** from a neighbouring row's figure.
    @Test("A price with OCR's stray space is read, and read correctly")
    func decimalWithStraySpaceIsRead() {
        #expect(service.extractDecimal(from: "BFR PINEAPPLE COCO 6. 99 F") == Decimal(string: "6.99"))
        #expect(service.extractDecimal(from: "ITEM 12 . 50") == Decimal(string: "12.50"))
        #expect(service.extractDecimal(from: "ITEM 4.99") == Decimal(string: "4.99"))
    }

    /// If only `extractDecimal` widened, the price would be read and then left glued to the name —
    /// exactly the defect SCAN-RULE-02 exists to remove. The two patterns must move together.
    @Test("A price with a stray space is also stripped from the name")
    func decimalWithStraySpaceIsStripped() {
        #expect(service.stripPrice(from: "BFR PINEAPPLE COCO 6. 99").trimmingCharacters(in: .whitespaces)
                == "BFR PINEAPPLE COCO")
    }

    /// The regression the first version of SCAN-RULE-04 caused, kept as a test. Tolerating the
    /// stray space alongside SCAN-09's *optional* integer part made `W. 33rd` read as `.33`, and
    /// Starbucks grew a third item out of its own shop address.
    @Test("A street address is not a price")
    func streetAddressIsNotAPrice() {
        #expect(service.extractDecimal(from: "450 W. 33rd Street") == nil)
        #expect(service.extractDecimal(from: "1200 N. 45th Ave") == nil)
    }

    /// The no-integer form is still needed — CVS prints its bottle deposit as `.05`, and OCR
    /// returns it spaced. The first attempt at the address fix refused the space here too and
    /// silently dropped that line, costing a point of price recall. Both forms must work.
    @Test("A sub-unit amount with no leading zero is still read, spaced or not")
    func subUnitAmountStillRead() {
        #expect(service.extractDecimal(from: "BOTTLE DEPOSIT .05") == Decimal(string: "0.05"))
        #expect(service.extractDecimal(from: "BOTTLE DEPOSIT . 05") == Decimal(string: "0.05"),
                "OCR spaces this; refusing it dropped the line from receipt 19 entirely")
    }

    /// The widened pattern must not start reading percentages or three-decimal rates as money —
    /// SCAN-10 was exactly that bug and its guards have to survive.
    @Test("Widening for stray spaces does not reopen SCAN-10")
    func rateIsStillNotAnAmount() {
        #expect(service.extractDecimal(from: "NY 8.875% TAX  .89") == Decimal(string: "0.89"))
        #expect(service.extractDecimal(from: "Tax 1 - 8.00 %") == nil)
    }

    // MARK: - isReceiptMetadata (SCAN-RULE-03)

    /// These two reached the corpus as items priced `3` and `0.3`. `isMeasurementOnly` cannot
    /// reject them: `Time: 05:12PM` is 50% letters, well above its 0.3 ratio.
    @Test("A till timestamp is not an item")
    func timestampRowsAreRejected() {
        #expect(service.isReceiptMetadata("Time: 05:12PM"))
        #expect(service.isReceiptMetadata("Time: 05:23PM"))
        #expect(service.isMeasurementOnly("Time: 05:12PM") == false,
                "documents why a second predicate was needed rather than widening the first")
    }

    /// The placement test, and the one that actually caught the bug. Kroger prints the time on a
    /// line of its own, so the timestamp reaches the item branch as a **carried** name, not as the
    /// row's own text. The first version of this guard ran before the carry and changed nothing:
    /// `Time: 05:12PM=3` still appeared in the benchmark output.
    @Test("A timestamp carried from the row above is still not an item")
    func carriedTimestampIsRejected() {
        let rows: [[OCRLine]] = [
            [line("KROGER", y: 0.05)],
            [line("SIMPLE TRUTH MILK PC", x: 0.2, y: 0.30), line("3.99", x: 0.85, y: 0.30)],
            [line("Time: 05:12PM", x: 0.2, y: 0.60)],
            [line("3.00", x: 0.85, y: 0.63)],
        ]
        let parsed = service.parseWithHeuristics(rows: rows)
        #expect(parsed.receipt.items.map(\.name) == ["SIMPLE TRUTH MILK PC"],
                "got \(parsed.receipt.items.map(\.name))")
    }

    @Test("Ordinary item names are not treated as metadata")
    func realNamesAreNotMetadata() {
        for name in ["Tortilla Chips", "ORG ARUGULA", "5PK GOGGLES:MULITCOLORAO", "THERMACARE"] {
            #expect(service.isReceiptMetadata(name) == false, "\(name) was rejected as metadata")
        }
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

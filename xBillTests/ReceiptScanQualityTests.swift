//
//  ReceiptScanQualityTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Three receipt-scanning defects, all in the pure text→receipt layer so they are testable without
//  a camera, an image, or Vision.
//
//  SCAN-01  a discount was parsed with the wrong sign
//  SCAN-02  the confidence shown to the user was a constant
//  SCAN-03  low-confidence rows were not distinguishable from clean ones
//

import Testing
import Foundation
@testable import xBill

@Suite("Receipt scanning — sign, confidence and flags")
@MainActor
struct ReceiptScanQualityTests {

    private var vision: VisionService { VisionService.shared }

    // MARK: - SCAN-01: discounts

    /// The original defect. The price pattern had no `-`, so `-2.00` extracted as `2.00`, passed
    /// the `> .zero` guard, and became a **+£2 item** — a £2 voucher moved the item sum £4 the
    /// wrong way and produced a mismatch warning with no visible cause.
    @Test("A leading minus is preserved, not stripped")
    func leadingMinusPreserved() {
        #expect(vision.extractDecimal(from: "VOUCHER -2.00") == Decimal(string: "-2.00"))
        #expect(vision.extractDecimal(from: "DISCOUNT -£1.50") == Decimal(string: "-1.50"))
    }

    /// Some tills print the sign after the number. OCR also frequently returns the Unicode minus
    /// `−` (U+2212) rather than ASCII `-`, and a pattern matching only ASCII silently misses it.
    @Test("Trailing and Unicode minus signs are recognised")
    func trailingAndUnicodeMinus() {
        #expect(vision.extractDecimal(from: "REFUND 3.00-") == Decimal(string: "-3.00"))
        #expect(vision.extractDecimal(from: "PROMO −4.25") == Decimal(string: "-4.25"))
    }

    /// The other direction — the sign work must not have broken ordinary prices, and `lastMatch`
    /// (M-12) must still pick the line total rather than the unit price.
    @Test("Positive prices are unchanged, and the rightmost value still wins")
    func positivesUnchanged() {
        #expect(vision.extractDecimal(from: "BURGER 9.98") == Decimal(string: "9.98"))
        #expect(vision.extractDecimal(from: "£12,50") == Decimal(string: "12.50"))
        #expect(vision.extractDecimal(from: "2x BURGER 4.99 9.98") == Decimal(string: "9.98"),
                "M-12: the line total, not the unit price.")
    }

    /// A discount is often printed as a *positive* number under a label, so the keyword check has
    /// to catch it even when the sign does not.
    @Test("Discount lines are recognised by wording as well as by sign")
    func discountKeywords() {
        #expect(vision.isDiscountLine("staff discount"))
        #expect(vision.isDiscountLine("10% off"))
        #expect(vision.isDiscountLine("loyalty voucher"))
        #expect(!vision.isDiscountLine("cheeseburger"),
                "An ordinary item must not be treated as a discount.")
    }

    // MARK: - SCAN-02: confidence

    private func line(_ text: String, _ confidence: Float) -> OCRLine {
        OCRLine(text: text, midX: 0.5, midY: 0.5, confidence: confidence)
    }

    /// The defect: every heuristic scan reported 0.75, or 0.55 with a warning. A crisp receipt and
    /// a blurred one were indistinguishable to the user.
    @Test("Confidence reflects the OCR, so different scans differ")
    func confidenceIsNotConstant() {
        let clean = VisionService.aggregateConfidence(
            [line("A", 0.98), line("B", 0.97), line("C", 0.99), line("D", 0.96)], hasWarning: false)
        let poor = VisionService.aggregateConfidence(
            [line("A", 0.42), line("B", 0.51), line("C", 0.38), line("D", 0.60)], hasWarning: false)

        #expect(clean > poor, "A clean scan must not score the same as a poor one.")
        #expect(clean > 0.9)
        #expect(poor < 0.6)
    }

    /// Averaging across many clean lines would hide the few misreads that actually change the
    /// total, so the weakest half is what counts.
    @Test("A few bad lines among many good ones still lower the score")
    func weakLinesAreNotAveragedAway() {
        let mostlyClean = (0..<8).map { line("ok\($0)", 0.99) }
        let withMisreads = mostlyClean + [line("bad1", 0.20), line("bad2", 0.25)]

        #expect(VisionService.aggregateConfidence(withMisreads, hasWarning: false)
                < VisionService.aggregateConfidence(mostlyClean, hasWarning: false))
    }

    /// A failed items-vs-total check is independent evidence of a misread, so it discounts the
    /// score — but must not replace it, or we are back to a constant.
    /// ⚠️ This assertion was originally weaker — it only checked `warned < clean` and `warned > 0`,
    /// both of which hold for the constant `hasWarning ? 0.55 : 0.75` this function replaced. It
    /// would have passed against the very defect it exists to prevent. Mutation testing caught it.
    /// The discriminating property is that a *warned* score still varies with the OCR: two
    /// receipts that both failed validation must not score identically if one was far cleaner.
    @Test("A warning lowers the score but the score still reflects the OCR")
    func warningPenalises() {
        let good = [line("A", 0.95), line("B", 0.93)]
        let bad  = [line("A", 0.40), line("B", 0.35)]

        let goodClean  = VisionService.aggregateConfidence(good, hasWarning: false)
        let goodWarned = VisionService.aggregateConfidence(good, hasWarning: true)
        let badWarned  = VisionService.aggregateConfidence(bad,  hasWarning: true)

        #expect(goodWarned < goodClean, "A warning must lower the score.")
        #expect(goodWarned > 0, "A warning must not zero out a legible scan.")
        #expect(goodWarned > badWarned,
                "Two warned receipts must still be distinguishable — a constant would tie them.")
    }

    @Test("No recognised text scores zero rather than defaulting high")
    func emptyScoresZero() {
        #expect(VisionService.aggregateConfidence([], hasWarning: false) == 0)
    }

    // MARK: - SCAN-04: reconciliation bounds

    private func parsed(_ name: String, _ price: String, alternates: [String] = []) -> ParsedItem {
        ParsedItem(item: ReceiptItem(name: name, unitPrice: Decimal(string: price)!),
                   candidatePrices: alternates.map { Decimal(string: $0)! })
    }

    /// The headline fix. A single misread digit — `18.99` read as `78.99` — is a **$60** gap, and
    /// the old `|delta| ≤ $2.00` cap refused to look at exactly this case. It is the shape OCR
    /// errors actually take.
    @Test("A large delta from one misread digit is now corrected")
    func largeDigitMisreadIsCorrected() {
        var items = [parsed("Steak", "78.99", alternates: ["18.99"]),
                     parsed("Water", "3.00")]
        let fixed = vision.reconcile(candidates: &items,
                                     total: Decimal(string: "21.99")!, tax: .zero, tip: .zero)

        #expect(fixed, "A $60 delta from a digit misread must be repairable.")
        #expect(items[0].item.unitPrice == Decimal(string: "18.99"))
    }

    /// The small-delta path must keep working — this is what the old cap did allow.
    @Test("A small delta is still corrected")
    func smallDeltaStillWorks() {
        var items = [parsed("Coffee", "4.50", alternates: ["3.50"]),
                     parsed("Cake", "5.00")]
        #expect(vision.reconcile(candidates: &items,
                                 total: Decimal(string: "8.50")!, tax: .zero, tip: .zero))
        #expect(items[0].item.unitPrice == Decimal(string: "3.50"))
    }

    /// No alternate closes the gap, so nothing is applied. This replaced a test for a magnitude
    /// bound that turned out to be both wrong and unfireable — see `reconcile`'s documentation.
    @Test("When no alternate closes the gap, nothing is mutated")
    func noViableAlternateLeavesItemsAlone() {
        var items = [parsed("Item", "5.00", alternates: ["500.00"])]
        let before = items[0].item.unitPrice
        #expect(!vision.reconcile(candidates: &items,
                                  total: Decimal(string: "10.00")!, tax: .zero, tip: .zero))
        #expect(items[0].item.unitPrice == before, "Nothing may be mutated on refusal.")
    }

    /// A zero or unparsed total gives nothing to reconcile against.
    @Test("A zero total is refused")
    func zeroTotalRefused() {
        var items = [parsed("Item", "5.00", alternates: ["4.00"])]
        #expect(!vision.reconcile(candidates: &items, total: .zero, tax: .zero, tip: .zero))
    }

    /// The correctness guard the old code lacked: it took the **first** substitution that closed
    /// the gap. When two different items could each explain it there is no evidence for choosing,
    /// and guessing writes a wrong price into someone's split.
    @Test("An ambiguous correction is refused rather than guessed")
    func ambiguousCorrectionIsRefused() {
        // Either item could drop by 1.00 to close a 1.00 gap — genuinely undecidable.
        var items = [parsed("A", "5.00", alternates: ["4.00"]),
                     parsed("B", "5.00", alternates: ["4.00"])]
        let fixed = vision.reconcile(candidates: &items,
                                     total: Decimal(string: "9.00")!, tax: .zero, tip: .zero)

        #expect(!fixed, "Two equally valid corrections must not be guessed between.")
        #expect(items[0].item.unitPrice == Decimal(string: "5.00"))
        #expect(items[1].item.unitPrice == Decimal(string: "5.00"))
    }

    /// An already-balanced receipt must be left alone — otherwise reconciliation could "correct" a
    /// correct receipt.
    @Test("A balanced receipt is not touched")
    func balancedReceiptUntouched() {
        var items = [parsed("A", "5.00", alternates: ["4.00"])]
        #expect(!vision.reconcile(candidates: &items,
                                  total: Decimal(string: "5.00")!, tax: .zero, tip: .zero))
        #expect(items[0].item.unitPrice == Decimal(string: "5.00"))
    }

    /// Tax and tip participate in the sum, so a correction has to account for them.
    @Test("Tax and tip are included in the reconciliation maths")
    func taxAndTipCounted() {
        var items = [parsed("Meal", "40.00", alternates: ["20.00"])]
        #expect(vision.reconcile(candidates: &items,
                                 total: Decimal(string: "25.00")!,
                                 tax: Decimal(string: "2.00")!,
                                 tip: Decimal(string: "3.00")!))
        #expect(items[0].item.unitPrice == Decimal(string: "20.00"))
    }

    // MARK: - SCAN-03: per-item confidence

    /// Defaults to certain, so the Tier 1 (LLM) path and hand-added items are never flagged —
    /// only the heuristic path has a Vision confidence to report.
    @Test("A hand-made item is certain by default")
    func itemDefaultsToCertain() {
        #expect(ReceiptItem(name: "Coffee", unitPrice: 3).confidence == 1)
    }

    @Test("An item's confidence is independently settable and survives a copy")
    func itemConfidenceIsCarried() {
        var item = ReceiptItem(name: "Blurry line", unitPrice: 9)
        item.confidence = 0.31
        let copy = item
        #expect(copy.confidence == 0.31)
    }
}

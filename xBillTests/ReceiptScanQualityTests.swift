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

    // MARK: - SCAN-05: receipt-level assignment

    @MainActor
    private func vmWithItems(members: Int = 3, meIsMember: Bool = true) -> (ReceiptViewModel, [UUID]) {
        let vm = ReceiptViewModel()
        let users = (0..<members).map {
            User(id: UUID(), email: "u\($0)@x.com", displayName: "User \($0)",
                 avatarURL: nil, createdAt: Date())
        }
        vm.members = users
        vm.currentUserID = meIsMember ? users.first?.id : UUID()
        vm.items = [ReceiptItem(name: "A", unitPrice: 5),
                    ReceiptItem(name: "B", unitPrice: 6),
                    ReceiptItem(name: "C", unitPrice: 7)]
        return (vm, users.map(\.id))
    }

    /// The point of the feature: one action instead of one tap per line.
    @Test("Assigning everyone covers every item at once")
    func everyoneCoversAllItems() {
        let (vm, ids) = vmWithItems()
        vm.assignEveryoneToAllItems()
        #expect(vm.items.allSatisfy { Set($0.assignedUserIDs) == Set(ids) })
        #expect(!vm.hasUnassignedItems)
    }

    @Test("Just me assigns only the current user, to every item")
    func justMeAssignsOnlySelf() {
        let (vm, ids) = vmWithItems()
        vm.assignOnlyMeToAllItems()
        #expect(vm.items.allSatisfy { $0.assignedUserIDs == [ids[0]] })
    }

    /// Silently assigning someone who is not in the group would build a split that cannot be
    /// saved, so this must do nothing rather than half-work.
    @Test("Just me is a no-op when the current user is not a member")
    func justMeNoOpForNonMember() {
        let (vm, _) = vmWithItems(meIsMember: false)
        vm.assignOnlyMeToAllItems()
        #expect(vm.items.allSatisfy { $0.assignedUserIDs.isEmpty },
                "A non-member must not be assigned to anything.")
    }

    @Test("Clear removes every assignment")
    func clearRemovesAll() {
        let (vm, _) = vmWithItems()
        vm.assignEveryoneToAllItems()
        vm.clearAllAssignments()
        #expect(vm.items.allSatisfy { $0.assignedUserIDs.isEmpty })
        #expect(vm.hasUnassignedItems)
    }

    /// Drives the active state on the chips. It must be exact, not "contains" — a receipt where
    /// everyone *plus* extra assignments exist is not "Everyone".
    @Test("allItemsAssigned is exact, and false when any row differs")
    func allItemsAssignedIsExact() {
        let (vm, ids) = vmWithItems()
        vm.assignEveryoneToAllItems()
        #expect(vm.allItemsAssigned(to: ids))

        vm.assign(userID: ids[0], to: vm.items[1].id)   // remove one person from one row
        #expect(!vm.allItemsAssigned(to: ids),
                "One differing row must clear the active state.")
    }

    /// A bulk action **replaces** rather than merges, so switching from Everyone to Just me does
    /// not leave the others attached.
    @Test("A later bulk action replaces the earlier one")
    func bulkActionsReplace() {
        let (vm, ids) = vmWithItems()
        vm.assignEveryoneToAllItems()
        vm.assignOnlyMeToAllItems()
        #expect(vm.items.allSatisfy { $0.assignedUserIDs == [ids[0]] })
    }

    /// Regression for the device-found defect: the review screen reached the manual path with
    /// `members` populated but `currentUserID` nil, so "Just me" was hidden. `startManually` now
    /// carries the user rather than relying on the view's `.onAppear` having fired first.
    @Test("startManually carries the current user, not just the members")
    func startManuallyCarriesCurrentUser() {
        let vm = ReceiptViewModel()
        let me = User(id: UUID(), email: "me@x.com", displayName: "Me",
                      avatarURL: nil, createdAt: Date())
        vm.startManually(members: [me], currentUserID: me.id)

        #expect(vm.currentUserID == me.id)
        #expect(vm.members.map(\.id) == [me.id])
    }

    /// Omitting it must not wipe a value already set by the view's `.onAppear` — the two paths
    /// coexist deliberately, and the later one must not undo the earlier.
    @Test("startManually without a user preserves one already set")
    func startManuallyPreservesExistingUser() {
        let vm = ReceiptViewModel()
        let existing = UUID()
        vm.currentUserID = existing
        vm.startManually(members: [])

        #expect(vm.currentUserID == existing, "A nil argument must not clear a known user.")
    }

    @Test("With no items, nothing claims to be assigned")
    func emptyReceiptIsNotAssigned() {
        let vm = ReceiptViewModel()
        vm.members = []
        #expect(!vm.allItemsAssigned(to: []))
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

// MARK: - SCAN-06: the name/price column split was a hardcoded x-position
//
// `parseWithHeuristics` split every row at a fixed `midX < 0.55`. A receipt does not know about
// that number, and two ordinary layouts break against it in opposite directions:
//
//   • prices sitting **left** of 0.55 (a narrow receipt, or a wide crop) land in the *name*
//     column, so the item name keeps the price text inside it;
//   • an item name extending **past** 0.55 lands in the *price* column, so the name is truncated
//     to whatever fell left of the line.
//
// Both produce a wrong review screen from a perfectly good OCR pass. The boundary is now measured
// from the receipt's own geometry, because prices are right-aligned and therefore announce where
// their column begins.

@Suite("Receipt scanning — price column detection")
@MainActor
struct ReceiptColumnDetectionTests {

    private var vision: VisionService { VisionService.shared }

    /// Builds one row per (name, price) pair at the given x-positions, plus a merchant row on top.
    /// `parseWithHeuristics` skips the first row as the merchant, so callers get exactly the item
    /// rows they asked for.
    private func rows(_ entries: [(name: String, nameX: CGFloat, price: String, priceX: CGFloat)])
    -> [[OCRLine]] {
        var out: [[OCRLine]] = [[OCRLine(text: "Cafe Luna", midX: 0.5, midY: 0.02, confidence: 0.99)]]
        for (i, e) in entries.enumerated() {
            let y = 0.1 + CGFloat(i) * 0.1
            out.append([
                OCRLine(text: e.name,  midX: e.nameX,  midY: y, confidence: 0.95),
                OCRLine(text: e.price, midX: e.priceX, midY: y, confidence: 0.95)
            ])
        }
        return out
    }

    // MARK: - The two failing layouts

    /// Prices left of the old 0.55 constant. Under the fixed split the price fell into the name
    /// column, `leftText` was non-empty so `stripPrice` never ran, and the item was named
    /// "Coffee 3.50" — the amount rendered twice on the review screen, once as text.
    @Test("A price column left of the old constant does not contaminate the item name")
    func priceColumnLeftOfDefaultKeepsNameClean() {
        let parsed = vision.parseWithHeuristics(rows: rows([
            ("Coffee", 0.12, "3.50", 0.45),
            ("Muffin", 0.12, "2.25", 0.45),
            ("Juice",  0.12, "4.00", 0.45)
        ]))
        let names = parsed.receipt.items.map(\.name)
        #expect(names.contains("Coffee"))
        #expect(!names.contains { $0.contains("3.50") },
                "The price must not survive inside the item name: \(names)")
    }

    /// The opposite direction: a name whose second word sits right of 0.55. Under the fixed split
    /// "Sandwich" was classified as price-column text and the item was named just "Chicken".
    @Test("A long name crossing the old constant is not truncated")
    func longNameCrossingDefaultIsNotTruncated() {
        let threeCol: [[OCRLine]] = [
            [OCRLine(text: "Cafe Luna", midX: 0.5, midY: 0.02, confidence: 0.99)],
            [OCRLine(text: "Chicken",  midX: 0.10, midY: 0.10, confidence: 0.95),
             OCRLine(text: "Sandwich", midX: 0.60, midY: 0.10, confidence: 0.95),
             OCRLine(text: "9.99",     midX: 0.90, midY: 0.10, confidence: 0.95)],
            [OCRLine(text: "Fries", midX: 0.10, midY: 0.20, confidence: 0.95),
             OCRLine(text: "3.00",  midX: 0.90, midY: 0.20, confidence: 0.95)],
            [OCRLine(text: "Water", midX: 0.10, midY: 0.30, confidence: 0.95),
             OCRLine(text: "2.00",  midX: 0.90, midY: 0.30, confidence: 0.95)]
        ]
        let parsed = vision.parseWithHeuristics(rows: threeCol)
        #expect(parsed.receipt.items.map(\.name).contains("Chicken Sandwich"),
                "Got \(parsed.receipt.items.map(\.name))")
    }

    // MARK: - The measurement itself

    @Test("A right-aligned price column is detected left of its own centre")
    func detectsRightAlignedColumn() {
        let b = vision.detectPriceColumnBoundary(rows: rows([
            ("Coffee", 0.10, "3.50", 0.90),
            ("Muffin", 0.10, "2.25", 0.90),
            ("Juice",  0.10, "4.00", 0.90)
        ]))
        #expect(b < 0.90, "The boundary must sit left of the prices, else they classify as names")
        #expect(b > 0.55, "A column at 0.90 must move the boundary right of the old constant")
    }

    /// One item row is not a column. With too little evidence the old constant is the safer answer
    /// than a boundary inferred from a single sample.
    @Test("Too few two-column rows falls back to the default boundary")
    func fallsBackWhenEvidenceIsThin() {
        let b = vision.detectPriceColumnBoundary(rows: rows([("Coffee", 0.10, "3.50", 0.90)]))
        #expect(b == VisionService.defaultPriceColumnBoundary)
    }

    /// Prices are right-aligned, so their centres cluster within the width variation of an amount.
    /// A wide spread means these rows are not one column and the measurement is not trustworthy.
    @Test("A scattered set of candidates is rejected rather than averaged")
    func wideSpreadIsRejected() {
        let b = vision.detectPriceColumnBoundary(rows: rows([
            ("Coffee", 0.10, "3.50", 0.40),
            ("Muffin", 0.10, "2.25", 0.90),
            ("Juice",  0.10, "4.00", 0.88)
        ]))
        #expect(b == VisionService.defaultPriceColumnBoundary)
    }

    /// A card line reads as a decimal and sits mid-width. Without the metadata filter it becomes
    /// the leftmost "price" and drags the boundary left across the whole receipt.
    @Test("A metadata row is not mistaken for the price column")
    func metadataDoesNotMoveTheBoundary() {
        let withCard: [[OCRLine]] = [
            [OCRLine(text: "Cafe Luna", midX: 0.5, midY: 0.02, confidence: 0.99)],
            [OCRLine(text: "VISA", midX: 0.10, midY: 0.10, confidence: 0.95),
             OCRLine(text: "12.34", midX: 0.70, midY: 0.10, confidence: 0.95)],
            [OCRLine(text: "Coffee", midX: 0.10, midY: 0.20, confidence: 0.95),
             OCRLine(text: "3.50",   midX: 0.90, midY: 0.20, confidence: 0.95)],
            [OCRLine(text: "Muffin", midX: 0.10, midY: 0.30, confidence: 0.95),
             OCRLine(text: "2.25",   midX: 0.90, midY: 0.30, confidence: 0.95)]
        ]
        let b = vision.detectPriceColumnBoundary(rows: withCard)
        #expect(b > 0.75, "The 0.70 card row must be excluded; got \(b)")
    }

    /// The floor. A detected column starting near the middle would classify most of the receipt as
    /// price once the margin is applied, which is never a real layout.
    @Test("The boundary never falls into the middle of the receipt")
    func boundaryIsFloored() {
        let b = vision.detectPriceColumnBoundary(rows: rows([
            ("Coffee", 0.05, "3.50", 0.40),
            ("Muffin", 0.05, "2.25", 0.40),
            ("Juice",  0.05, "4.00", 0.40)
        ]))
        #expect(b == VisionService.priceColumnFloor)
    }
}

// MARK: - SCAN-07: the exposure gate refused every dark-mode digital receipt
//
// `checkImageQuality` rejected anything whose MEAN luminance fell below a floor, with
// "Image is too dark — move to better lighting and try again." A dark-mode receipt screenshot is
// mostly black by design, so all three in the benchmark corpus were refused before OCR ran — and
// the advice offered is meaningless for a screenshot of an email.
//
// Mean luminance alone cannot separate the two cases. What separates them is whether any
// meaningful population of BRIGHT pixels exists: white text on black has one, an underexposed
// photograph of paper does not.

@Suite("Receipt scanning — exposure verdict")
struct ExposureVerdictTests {

    /// White text on a black background: low mean, but a real bright population.
    @Test("A dark-mode screenshot is accepted, not called too dark")
    func darkModeScreenshotAccepted() {
        #expect(VisionService.exposureVerdict(meanLuminance: 0.08, brightFraction: 0.06, darkFraction: 0.80) == .acceptable)
        #expect(VisionService.exposureVerdict(meanLuminance: 0.04, brightFraction: 0.12, darkFraction: 0.85) == .acceptable)
    }

    /// The case the floor exists for: everything crushed dark, nothing bright anywhere.
    @Test("An underexposed photograph is still rejected")
    func underexposedPhotoRejected() {
        #expect(VisionService.exposureVerdict(meanLuminance: 0.08, brightFraction: 0.001, darkFraction: 0.99) == .tooDark)
        #expect(VisionService.exposureVerdict(meanLuminance: 0.02, brightFraction: 0.0, darkFraction: 1.0) == .tooDark)
    }

    /// The bright-population test must be able to fail, or it is decoration: just below the
    /// threshold, a dark image is still refused.
    @Test("The bright-pixel guard can fire")
    func brightGuardCanFire() {
        let below = VisionService.brightFractionFloor - 0.001
        let above = VisionService.brightFractionFloor + 0.001
        #expect(VisionService.exposureVerdict(meanLuminance: 0.05, brightFraction: below, darkFraction: 0.9) == .tooDark)
        #expect(VisionService.exposureVerdict(meanLuminance: 0.05, brightFraction: above, darkFraction: 0.9) == .acceptable)
    }

    /// Glare is unaffected by this work and must stay rejected — including the perverse case of a
    /// blown-out image, which trivially has a large bright population.
    /// A blown-out frame: nothing dark survives, so there is no text left to read.
    @Test("A genuinely blown-out frame is still rejected")
    func overexposedRejected() {
        #expect(VisionService.exposureVerdict(meanLuminance: 0.95, brightFraction: 0.99,
                                              darkFraction: 0.001) == .tooBright)
    }

    /// SCAN-08, the mirror of the dark case. White thermal paper filling the viewfinder has a very
    /// high mean — that is what a GOOD receipt photo looks like — but its printed text survives as
    /// a real dark population. The airport Starbucks receipt was refused as "too bright" for
    /// exactly this reason.
    @Test("A well-lit white receipt is accepted, not called too bright")
    func whitePaperAccepted() {
        #expect(VisionService.exposureVerdict(meanLuminance: 0.94, brightFraction: 0.9,
                                              darkFraction: 0.06) == .acceptable)
    }

    /// The dark-population test must be able to fail, or it is decoration.
    @Test("The dark-pixel guard can fire")
    func darkGuardCanFire() {
        let below = VisionService.darkFractionFloor - 0.001
        let above = VisionService.darkFractionFloor + 0.001
        #expect(VisionService.exposureVerdict(meanLuminance: 0.95, brightFraction: 0.9,
                                              darkFraction: below) == .tooBright)
        #expect(VisionService.exposureVerdict(meanLuminance: 0.95, brightFraction: 0.9,
                                              darkFraction: above) == .acceptable)
    }

    @Test("An ordinary receipt photo is accepted")
    func normalAccepted() {
        #expect(VisionService.exposureVerdict(meanLuminance: 0.70, brightFraction: 0.65, darkFraction: 0.20) == .acceptable)
    }
}

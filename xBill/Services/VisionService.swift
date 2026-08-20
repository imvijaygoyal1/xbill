//
//  VisionService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Vision
import UIKit
import CoreImage
import NaturalLanguage

// MARK: - OCRLine

struct OCRLine: Sendable {
    let text:       String
    let midX:       CGFloat   // 0 = left edge, 1 = right edge
    let midY:       CGFloat   // 0 = top of image, 1 = bottom (Y-flipped from Vision)
    let confidence: Float
    let alternates: [String]  // other OCR candidate strings for this observation (Gap 7)

    init(text: String, midX: CGFloat, midY: CGFloat, confidence: Float, alternates: [String] = []) {
        self.text       = text
        self.midX       = midX
        self.midY       = midY
        self.confidence = confidence
        self.alternates = alternates
    }
}

// MARK: - ScanResult

struct ScanResult: Sendable {
    let receipt:           Receipt
    let confidence:        Double
    let tier:              String    // "Apple Intelligence" or "Heuristic"
    let validationWarning: String?
    let suggestedCategory: Expense.Category?
}

// Internal helper for Gap 7: bundles a parsed item with the alternate prices
// extracted from OCR candidate strings for that row, enabling constraint-solving.
/// Module-internal rather than private **so the parsing core can be tested directly**.
/// `VisionService` was 3.7% covered: the pure text→receipt logic — the part that turns OCR text
/// into money — was unreachable from tests because every function was `private`, while the
/// remainder is Vision/CoreImage plumbing that needs real images. Nothing here is public API.
struct ParsedItem: Sendable {
    var item:            ReceiptItem
    var candidatePrices: [Decimal]
}

// MARK: - VisionService

@MainActor
final class VisionService {
    static let shared = VisionService()
    private init() {}

    // Shared CIContext — Metal GPU pipeline is expensive to create; reuse across all calls.
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // Receipt domain vocabulary injected into Vision to improve recognition accuracy.
    private static let receiptCustomWords: [String] = [
        "SUBTOTAL", "TAX", "TIP", "GRATUITY", "TOTAL", "GRAND TOTAL",
        "TOTAL DUE", "AMOUNT DUE", "BALANCE DUE", "SERVICE CHARGE",
        "GST", "HST", "VAT", "INCL", "EXCL", "COMP", "VOID",
        "QTY", "EACH", "SVC", "SVCHRG", "SURCHARGE", "CASHBACK",
        "VISA", "MASTERCARD", "AMEX", "CONTACTLESS", "CHIP"
    ]

    // MARK: - Public Entry Points

    func scanReceipt(from image: UIImage) async throws -> ScanResult {
        try checkImageQuality(image)
        return try await processScan(images: [image])
    }

    /// Processes all pages from a multi-page document scan, combining OCR results.
    func scanMultiPage(from images: [UIImage]) async throws -> ScanResult {
        guard !images.isEmpty else {
            throw AppError.validationFailed("No pages captured.")
        }
        if let first = images.first { try checkImageQuality(first) }
        return try await processScan(images: images)
    }

    // MARK: - Core Pipeline

    private func processScan(images: [UIImage]) async throws -> ScanResult {
        let pageCount = Double(images.count)

        // OCR each page; shift Y so pages stack vertically without overlap
        var allLines: [OCRLine] = []
        for (pageIndex, image) in images.enumerated() {
            // M-22: run quality check on every page, not just the first.
            // A blurry page 2+ would otherwise silently contribute garbage OCR lines.
            // Page 0 was already checked by scanReceipt / scanMultiPage before calling
            // processScan, but subsequent pages have not been validated yet.
            if pageIndex > 0 {
                do {
                    try checkImageQuality(image)
                } catch {
                    // Skip the blurry/dark page and continue with the rest rather than
                    // aborting the entire scan — partial results are better than none.
                    continue
                }
            }
            let pageLines = try await recognizeText(in: image)
            let offset    = Double(pageIndex)
            allLines += pageLines.map { line in
                OCRLine(text:       line.text,
                        midX:       line.midX,
                        midY:       (line.midY + offset) / pageCount,
                        confidence: line.confidence,
                        alternates: line.alternates)   // preserve alternates for Gap 7
            }
        }

        // Adjust spatial threshold proportionally to number of pages
        let rowThreshold = CGFloat(0.025 / pageCount)
        let rows         = groupIntoRows(allLines, threshold: rowThreshold)
        let ocrText      = rows.map { $0.map(\.text).joined(separator: " ") }.joined(separator: "\n")

        let txDate       = extractTransactionDate(from: ocrText)
        let detectedLang = detectLanguage(from: ocrText)

        // Tier 1 — Apple Foundation Models (iOS 26+, Apple Intelligence device)
        if #available(iOS 26.0, *) {
            let fm = FoundationModelService.shared
            if fm.isAvailable {
                do {
                    let parsed  = try await fm.parseReceipt(ocrText: ocrText, language: detectedLang)
                    var receipt = convert(parsed)
                    // Prefer AI-extracted date (clean string); fall back to NSDataDetector hit
                    receipt.transactionDate = parsed.transactionDate
                        .flatMap { extractTransactionDate(from: $0) } ?? txDate
                    let warning  = validate(receipt, parsed: parsed)
                    let category = suggestCategory(merchant: receipt.merchant, items: receipt.items)
                    return ScanResult(
                        receipt:           receipt,
                        confidence:        parsed.confidence,
                        tier:              "Apple Intelligence",
                        validationWarning: warning,
                        suggestedCategory: category
                    )
                } catch {
                    // Fall through to heuristics
                }
            }
        }

        // Tier 2 — Improved heuristics (all devices, iOS 17+)
        let (parsedReceipt, candidates) = parseWithHeuristics(rows: rows)
        var receipt = parsedReceipt
        receipt.transactionDate = txDate

        // Gap 7: Attempt constraint-solving when math fails and delta is small enough
        // to be a single-digit OCR misread rather than a structural parse failure.
        // L-24: Cache the validation result to avoid calling validateHeuristic twice.
        var mutableCandidates = candidates
        let initialWarning = validateHeuristic(receipt)
        let warning: String?
        if let total = receipt.total,
           initialWarning != nil,
           reconcile(candidates: &mutableCandidates, total: total,
                     tax: receipt.tax ?? .zero, tip: receipt.tip ?? .zero) {
            receipt.items = mutableCandidates.map(\.item)
            warning = nil
        } else {
            warning = initialWarning
        }

        let category = suggestCategory(merchant: receipt.merchant, items: receipt.items)
        return ScanResult(
            receipt:           receipt,
            // Derived from the OCR line confidences rather than a constant — see
            // `aggregateConfidence`. `allLines` is the recognised text this receipt was built from.
            confidence:        Self.aggregateConfidence(allLines, hasWarning: warning != nil),
            tier:              "Heuristic",
            validationWarning: warning,
            suggestedCategory: category
        )
    }

    // MARK: - Gap 2: Image Quality Gate

    /// Throws a user-facing `AppError.validationFailed` if the image is too dark,
    /// too blurry, or contains no detectable text. All checks use free on-device APIs.
    private func checkImageQuality(_ image: UIImage) throws {
        guard let cgImage = image.cgImage else { return }
        let ciImage = CIImage(cgImage: cgImage)
        let context = VisionService.ciContext

        // Exposure. SCAN-07: the mean alone is not enough — see `exposureVerdict`.
        if let luminance = averageLuminance(ciImage, context: context) {
            let tones = toneFractions(ciImage, context: context)
            switch Self.exposureVerdict(meanLuminance: Double(luminance),
                                        brightFraction: Double(tones?.bright ?? 0),
                                        darkFraction:   Double(tones?.dark   ?? 0)) {
            case .tooDark:
                throw AppError.validationFailed("Image is too dark — move to better lighting and try again.")
            case .tooBright:
                throw AppError.validationFailed("Image is too bright — reduce glare or avoid direct flash.")
            case .acceptable:
                break
            }
        }

        // Blur: average Laplacian edge energy < 2% → too blurry for OCR
        if let edgeEnergy = laplacianEdgeEnergy(ciImage, context: context), edgeEnergy < 0.02 {
            throw AppError.validationFailed("Image is too blurry — hold the camera steady and retake.")
        }

        // Text presence: fast rectangle scan before the expensive accurate OCR
        if !hasTextRegions(cgImage: cgImage) {
            throw AppError.validationFailed("No text detected — make sure the receipt is clearly visible.")
        }
    }

    // MARK: - Exposure (SCAN-07)

    enum ExposureVerdict: Equatable, Sendable { case acceptable, tooDark, tooBright }

    /// Below this mean the image is a candidate for rejection — but only a candidate.
    nonisolated static let darkMeanFloor: Double = 0.12
    /// Above this mean it is glare, and no bright-population argument rescues it.
    nonisolated static let brightMeanCeiling: Double = 0.92
    /// A pixel at or above this luminance counts as "bright".
    nonisolated static let brightPixelThreshold: Float = 0.5
    /// The share of bright pixels that distinguishes light-on-dark content from underexposure.
    /// White text occupies a small fraction of a screen, so this is deliberately low; an
    /// underexposed photograph of paper has essentially none.
    nonisolated static let brightFractionFloor: Double = 0.01
    /// A pixel at or below this luminance counts as "dark".
    nonisolated static let darkPixelThreshold: Float = 0.35
    /// SCAN-08, the mirror of the above: the share of dark pixels that distinguishes white paper
    /// from a blown-out frame. Printed text is a small fraction of a receipt's area, so this is
    /// low too; a genuinely overexposed photograph has almost no dark pixels left.
    nonisolated static let darkFractionFloor: Double = 0.01

    /// Decides exposure from two measurements rather than one.
    ///
    /// The mean alone conflates two situations that need opposite answers, at **both** ends.
    ///
    /// Dark end: an **underexposed photograph**, where nothing is legible and the user must
    /// retake it, versus a **correctly exposed inverted image** — a dark-mode receipt screenshot,
    /// perfectly legible and a normal way to hold a receipt. Both have a low mean; only the
    /// second has a real population of bright pixels, because its text is white.
    ///
    /// Bright end (SCAN-08): a **blown-out frame** versus **white thermal paper filling the
    /// viewfinder**, which is what a good receipt photo looks like. Both have a high mean; only
    /// the second still has dark pixels, because its text survived.
    ///
    /// In both directions the rule is the same: a high mean is only a problem if the *other*
    /// tone has been destroyed.
    ///
    /// Pure and `nonisolated` — it reads no state, so callers need not hop to the main actor to
    /// ask a question about two numbers. `checkImageQuality` supplies the measurements.
    nonisolated static func exposureVerdict(meanLuminance: Double,
                                            brightFraction: Double,
                                            darkFraction: Double) -> ExposureVerdict {
        if meanLuminance > brightMeanCeiling && darkFraction  < darkFractionFloor   { return .tooBright }
        if meanLuminance < darkMeanFloor     && brightFraction < brightFractionFloor { return .tooDark }
        return .acceptable
    }

    /// Fractions of pixels at or above `brightPixelThreshold` and at or below `darkPixelThreshold`.
    ///
    /// Sampled at 256px rather than smaller: downscaling averages thin white strokes toward the
    /// background, and at 64px a page of dark-mode text loses its bright population entirely —
    /// which would reintroduce the very defect this measurement exists to prevent.
    private func toneFractions(_ image: CIImage, context: CIContext) -> (bright: Float, dark: Float)? {
        let longest = max(image.extent.width, image.extent.height)
        guard longest > 0 else { return nil }
        let scale  = min(256.0 / longest, 1.0)
        let scaled = scale < 1.0
            ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : image

        let w = max(Int(scaled.extent.width), 1)
        let h = max(Int(scaled.extent.height), 1)
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        context.render(scaled, toBitmap: &buffer, rowBytes: w * 4,
                       bounds: CGRect(x: 0, y: 0, width: w, height: h),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        var brightCount = 0
        var darkCount   = 0
        for i in stride(from: 0, to: buffer.count, by: 4) {
            let luma = (Float(buffer[i]) * 0.299 + Float(buffer[i + 1]) * 0.587
                        + Float(buffer[i + 2]) * 0.114) / 255.0
            if luma >= Self.brightPixelThreshold { brightCount += 1 }
            if luma <= Self.darkPixelThreshold   { darkCount   += 1 }
        }
        let total = Float(w * h)
        return (Float(brightCount) / total, Float(darkCount) / total)
    }

    private func averageLuminance(_ image: CIImage, context: CIContext) -> Float? {
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }
        var pixel = [Float](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 16,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf, colorSpace: nil)
        return (pixel[0] + pixel[1] + pixel[2]) / 3.0
    }

    // Average edge response via CIEdges on a downscaled grayscale image.
    private func laplacianEdgeEnergy(_ image: CIImage, context: CIContext) -> Float? {
        // Downscale for speed (max 512px on longest side)
        let scale  = min(512.0 / max(image.extent.width, image.extent.height), 1.0)
        let scaled = scale < 1.0
            ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : image

        guard let grayFilter = CIFilter(name: "CIPhotoEffectNoir") else { return nil }
        grayFilter.setValue(scaled, forKey: kCIInputImageKey)
        guard let grayImage = grayFilter.outputImage else { return nil }

        guard let edgesFilter = CIFilter(name: "CIEdges") else { return nil }
        edgesFilter.setValue(grayImage, forKey: kCIInputImageKey)
        edgesFilter.setValue(1.0, forKey: kCIInputIntensityKey)
        guard let edgeImage = edgesFilter.outputImage else { return nil }

        guard let avgFilter = CIFilter(name: "CIAreaAverage") else { return nil }
        avgFilter.setValue(edgeImage, forKey: kCIInputImageKey)
        avgFilter.setValue(CIVector(cgRect: grayImage.extent), forKey: kCIInputExtentKey)
        guard let avgOutput = avgFilter.outputImage else { return nil }

        var pixel = [Float](repeating: 0, count: 4)
        context.render(avgOutput, toBitmap: &pixel, rowBytes: 16,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf, colorSpace: nil)
        return pixel[0]
    }

    // Fast text-rectangle scan — no AI, just detects regions with text-like structure.
    private func hasTextRegions(cgImage: CGImage) -> Bool {
        let request = VNDetectTextRectanglesRequest()
        request.reportCharacterBoxes = false
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return (request.results?.isEmpty == false)
    }

    // MARK: - Gap 1: Core Image Pre-Processing Pipeline

    /// Applies grayscale, contrast boost, and sharpening before OCR.
    /// Produces cleaner text edges which reduces character misreads.
    /// Each step has a graceful fallback — if a filter is unavailable the
    /// pipeline continues with whatever it has so far.
    private func preprocessForOCR(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        var current = CIImage(cgImage: cgImage)

        // 1. Resize to max 1200px — bounds memory and processing time
        let maxDim: CGFloat = 1200
        let longestSide = max(current.extent.width, current.extent.height)
        if longestSide > maxDim {
            let scale = maxDim / longestSide
            current = current.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        // 2. Grayscale — receipt text is monochrome; colour channels add noise
        if let f = CIFilter(name: "CIPhotoEffectNoir") {
            f.setValue(current, forKey: kCIInputImageKey)
            if let out = f.outputImage { current = out }
        }

        // 3. Contrast 1.4× + brightness +0.05 — darkens ink, lightens paper background
        if let f = CIFilter(name: "CIColorControls") {
            f.setValue(current, forKey: kCIInputImageKey)
            f.setValue(1.4 as CGFloat, forKey: kCIInputContrastKey)
            f.setValue(0.05 as CGFloat, forKey: kCIInputBrightnessKey)
            if let out = f.outputImage { current = out }
        }

        // 4. Sharpness 0.4 — reinforces text edges for higher-confidence character recognition
        if let f = CIFilter(name: "CISharpenLuminance") {
            f.setValue(current, forKey: kCIInputImageKey)
            f.setValue(0.4 as CGFloat, forKey: kCIInputSharpnessKey)
            if let out = f.outputImage { current = out }
        }

        guard let outputCG = Self.ciContext.createCGImage(current, from: current.extent) else { return image }
        return UIImage(cgImage: outputCG)
    }

    // MARK: - Gap 3: Enhanced OCR Configuration

    private func recognizeText(in image: UIImage) async throws -> [OCRLine] {
        // Gap 1: preprocess before extracting cgImage for OCR
        let processed = preprocessForOCR(image)
        guard let cgImage = processed.cgImage else {
            throw AppError.validationFailed("Cannot process image — invalid format.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: AppError.from(error))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                // Gap 3: top 3 candidates — best goes into text, rest stored as alternates for Gap 7
                let lines: [OCRLine] = observations.compactMap { obs in
                    let candidates = obs.topCandidates(3)
                    guard let best = candidates.first(where: {
                        !$0.string.trimmingCharacters(in: .whitespaces).isEmpty
                    }) else { return nil }
                    let alts = candidates.dropFirst().map(\.string)
                    return OCRLine(
                        text:       best.string,
                        midX:       obs.boundingBox.midX,
                        midY:       1 - obs.boundingBox.midY,
                        confidence: best.confidence,
                        alternates: Array(alts)
                    )
                }
                continuation.resume(returning: lines)
            }

            request.recognitionLevel       = .accurate
            request.usesLanguageCorrection = true
            // Filter tiny footnotes (loyalty text, legal disclaimers < 1.5% of image height)
            request.minimumTextHeight      = 0.015
            // Inject receipt domain vocabulary so Vision prefers known terms over phonetic guesses
            request.customWords            = Self.receiptCustomWords
            // Prefer device locales first, always include English as fallback
            request.recognitionLanguages   = preferredRecognitionLanguages()

            // L-12: Pass image orientation so Vision correctly interprets rotated receipts.
            // Without this, VNImageRequestHandler assumes .up and produces garbage OCR on
            // portrait photos taken with the device rotated (e.g. landscape shots of receipts).
            let orientation = CGImagePropertyOrientation(image.imageOrientation)
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: AppError.from(error))
            }
        }
    }

    private func preferredRecognitionLanguages() -> [String] {
        var langs = Array(Locale.preferredLanguages.prefix(3))
        if !langs.contains(where: { $0.hasPrefix("en") }) {
            langs.append("en-US")
        }
        return langs
    }

    // MARK: - Spatial Grouping

    // MARK: Price column detection (SCAN-06)
    //
    // The name/price split used to be a hardcoded `midX < 0.55`. A receipt knows nothing about
    // that number, and it fails in both directions: a price column left of it contaminates the
    // item name with the price text, and an item name reaching past it gets truncated.
    //
    // Prices are **right-aligned** on essentially every receipt, which is the signal exploited
    // here: the rightmost element of a two-column row is the price, so the left edge of where
    // those elements sit is the column boundary.

    /// Used when the receipt's geometry gives no trustworthy measurement. This is the historical
    /// constant, kept as the fallback rather than the rule.
    static let defaultPriceColumnBoundary: CGFloat = 0.55

    /// The boundary never moves further left than this. A price column beginning mid-receipt
    /// would classify most of every row as price, which is not a layout that exists.
    static let priceColumnFloor: CGFloat = 0.35

    /// Right-alignment fixes the *right* edge of an amount, so its centre still shifts with the
    /// number's width — `1234.56` sits measurably left of `9.99`. The boundary is pulled this far
    /// left of the leftmost observed price so a long amount on one row is not misfiled as a name.
    static let priceColumnMargin: CGFloat = 0.08

    /// Above this spread the candidates are not one column, so the measurement is discarded.
    /// Width variation between amounts is small; anything wider means something other than a
    /// price column was measured.
    static let priceColumnSpreadLimit: CGFloat = 0.30

    /// Measures where the price column begins, in normalised image x.
    ///
    /// Only rows with at least two elements can teach anything — a single-element row has no
    /// split to make. Metadata rows are excluded because a card or reference number parses as a
    /// decimal and would drag the boundary left across the entire receipt.
    func detectPriceColumnBoundary(rows: [[OCRLine]]) -> CGFloat {
        let samples: [CGFloat] = rows.compactMap { row in
            guard row.count >= 2 else { return nil }
            let joined = row.map(\.text).joined(separator: " ").lowercased()
            guard !isMetadata(joined) else { return nil }
            // The rightmost element of a two-column row is the price — taking only that one is
            // what keeps a number embedded in an item name from being read as a column position.
            guard let rightmost = row.max(by: { $0.midX < $1.midX }),
                  extractDecimal(from: rightmost.text) != nil else { return nil }
            return rightmost.midX
        }

        // One sample is a coincidence, not a column.
        guard samples.count >= 2, let low = samples.min(), let high = samples.max() else {
            return Self.defaultPriceColumnBoundary
        }
        guard high - low <= Self.priceColumnSpreadLimit else {
            return Self.defaultPriceColumnBoundary
        }
        return max(low - Self.priceColumnMargin, Self.priceColumnFloor)
    }

    /// Groups OCR lines into visual rows by their Y coordinate.
    /// O(n log n) — sorts once then makes a single forward pass, assigning each line to an
    /// existing row whose anchor Y is within `threshold`, or opening a new row.
    /// This replaces the previous O(n²) implementation that re-scanned remaining lines for
    /// every anchor element.
    func groupIntoRows(_ lines: [OCRLine], threshold: CGFloat = 0.025) -> [[OCRLine]] {
        let sorted = lines.sorted { $0.midY < $1.midY }
        // `rowAnchors` holds the representative midY for each open row; index matches `rows`.
        var rowAnchors: [CGFloat] = []
        var rows: [[OCRLine]] = []

        for line in sorted {
            // Find the first existing row whose anchor Y is within threshold of this line.
            if let idx = rowAnchors.firstIndex(where: { abs($0 - line.midY) <= threshold }) {
                rows[idx].append(line)
                // Update anchor to the running mean so steeply slanted lines don't drift.
                rowAnchors[idx] = (rowAnchors[idx] + line.midY) / 2
            } else {
                rowAnchors.append(line.midY)
                rows.append([line])
            }
        }
        // Sort each row's lines by horizontal position (left → right).
        return rows.map { $0.sorted { $0.midX < $1.midX } }
    }

    // MARK: - OCR confidence

    /// A receipt-level confidence derived from the **actual** OCR line confidences.
    ///
    /// This replaced a constant. Tier 2 previously reported `0.75`, or `0.55` when a validation
    /// warning fired — so a crisp receipt in good light and a blurred one at an angle showed the
    /// user an identical number, while `OCRLine.confidence` was captured from Vision for every
    /// line and read nowhere. A fabricated score is worse than none, because it invites trust it
    /// has not earned.
    ///
    /// Uses the **mean of the weakest half** rather than the overall mean: a receipt is only as
    /// trustworthy as the lines that were hardest to read, and averaging across many clean lines
    /// hides the few misreads that actually change the total.
    static func aggregateConfidence(_ lines: [OCRLine], hasWarning: Bool) -> Double {
        let scores = lines.map { Double($0.confidence) }.sorted()
        guard !scores.isEmpty else { return 0 }
        let weakestHalf = scores.prefix(max(1, scores.count / 2))
        let mean = weakestHalf.reduce(0, +) / Double(weakestHalf.count)
        // A failed items-vs-total check is independent evidence that something was misread, so it
        // discounts the score rather than replacing it.
        let penalised = hasWarning ? mean * 0.6 : mean
        return min(max(penalised, 0), 1)
    }

    // MARK: - Gap 5: Language Detection (NaturalLanguage)

    /// Returns BCP-47 language tag (e.g. "fr", "de") or nil if undetermined.
    /// Used to give Apple Intelligence cultural context for non-English receipts.
    private func detectLanguage(from text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage,
              dominant != .undetermined else { return nil }
        return dominant.rawValue
    }

    // MARK: - Gap 4: Transaction Date Extraction

    /// Scans OCR text for the first plausible transaction date using NSDataDetector.
    /// Rejects future dates (> tomorrow) and dates more than 5 years old.
    func extractTransactionDate(from text: String) -> Date? {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        ) else { return nil }

        let range   = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)

        let now         = Date()
        let fiveYearsAgo = Calendar.current.date(byAdding: .year, value: -5, to: now) ?? now
        let tomorrow    = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now

        // Prefer the date closest to today (most likely the actual transaction date)
        return matches
            .compactMap(\.date)
            .filter { $0 >= fiveYearsAgo && $0 <= tomorrow }
            .min(by: { abs($0.timeIntervalSinceNow) < abs($1.timeIntervalSinceNow) })
    }

    // MARK: - Gap 5: Auto-Category from Merchant / Items

    /// Keyword-based category suggestion; on-device, no network.
    func suggestCategory(merchant: String?, items: [ReceiptItem]) -> Expense.Category? {
        let searchText = ([merchant] + items.map(\.name))
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        let matchers: [(Expense.Category, [String])] = [
            (.food,          ["restaurant", "cafe", "coffee", "pizza", "sushi", "burger",
                              "food", "diner", "grill", "bar", "pub", "kitchen", "bakery",
                              "deli", "bistro", "starbucks", "mcdonald", "chipotle", "subway",
                              "doordash", "ubereats", "grubhub", "tavern", "brasserie"]),
            (.transport,     ["uber", "lyft", "taxi", "gas", "fuel", "parking", "transit",
                              "airline", "flight", "amtrak", "station", "airport", "car rental",
                              "hertz", "avis", "enterprise", "metro", "train", "bus", "petrol"]),
            (.health,        ["pharmacy", "cvs", "walgreens", "hospital", "clinic", "drug",
                              "medical", "dental", "optometry", "health", "vitamin", "rite aid",
                              "chemist", "apotheke"]),
            (.accommodation, ["hotel", "airbnb", "hostel", "inn", "resort", "motel", "lodging",
                              "marriott", "hilton", "hyatt", "sheraton", "suite", "bnb"]),
            (.entertainment, ["cinema", "movie", "theater", "concert", "ticketmaster",
                              "spotify", "netflix", "amc", "regal", "imax", "bowling",
                              "museum", "arcade", "games", "event"]),
            (.shopping,      ["amazon", "walmart", "target", "costco", "mall", "store",
                              "shop", "market", "best buy", "apple store", "ikea",
                              "zara", "gap", "nordstrom", "h&m", "supermarket"]),
            (.utilities,     ["electric", "water", "internet", "phone", "broadband",
                              "utility", "comcast", "verizon", "at&t", "gas bill",
                              "energy", "power bill"]),
        ]

        for (category, keywords) in matchers {
            if keywords.contains(where: { searchText.contains($0) }) {
                return category
            }
        }
        return nil
    }

    // MARK: - Tier 2: Improved Heuristics

    func parseWithHeuristics(rows: [[OCRLine]]) -> (receipt: Receipt, candidates: [ParsedItem]) {
        var parsedItems: [ParsedItem] = []
        var total:    Decimal?
        var tax:      Decimal?
        var tip:      Decimal?
        var merchant: String?
        var currency  = "USD"

        // Common receipt header noise that should not be used as the merchant name.
        // These all-caps phrases appear at the top of many receipts as store taglines,
        // POS system headers, or social messages rather than the actual business name.
        let merchantNoisePatterns: Set<String> = [
            "THANK YOU", "WELCOME", "HAVE A NICE DAY", "RECEIPT",
            "CUSTOMER COPY", "STORE COPY", "PLEASE COME AGAIN",
            "VISIT US AGAIN", "THANK YOU FOR SHOPPING"
        ]
        // Walk rows from the top; skip all-caps lines that match known noise patterns.
        // Fall back to the very first row if all candidates are noise.
        for row in rows {
            let candidate = row.map(\.text).joined(separator: " ")
            let trimmed   = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let upper     = trimmed.uppercased()
            guard merchantNoisePatterns.contains(upper) else {
                merchant = trimmed.isEmpty ? nil : trimmed
                break
            }
        }

        // Currency from any symbol found anywhere in the text
        // M-13: added ¥/￥ → JPY and ₩ → KRW
        let allText = rows.flatMap { $0 }.map(\.text).joined()
        if allText.contains("£")                            { currency = "GBP" }
        else if allText.contains("€")                      { currency = "EUR" }
        else if allText.contains("₹")                      { currency = "INR" }
        else if allText.contains("¥") || allText.contains("￥") { currency = "JPY" }
        else if allText.contains("₩")                      { currency = "KRW" }

        // SCAN-06: measured from this receipt's own geometry rather than assumed. Computed once
        // for the whole receipt — the price column is a property of the layout, not of a row.
        let columnBoundary = detectPriceColumnBoundary(rows: rows)

        for row in rows.dropFirst() {
            let fullText = row.map(\.text).joined(separator: " ")
            let lower    = fullText.lowercased()

            if isMetadata(lower) { continue }

            let leftLines   = row.filter { $0.midX < columnBoundary }
            let rightLines  = row.filter { $0.midX >= columnBoundary }
            let leftText    = leftLines.map(\.text).joined(separator: " ")
            let rightText   = rightLines.map(\.text).joined(separator: " ")
            let priceSource = rightText.isEmpty ? fullText : rightText

            guard let rawAmount = extractDecimal(from: priceSource), rawAmount != .zero else { continue }
            // A discount is a real line on the receipt and must survive to the review screen; if it
            // is dropped, items no longer sum to the total and the user sees an unexplained
            // mismatch. Normalised to a negative so the arithmetic works without special cases.
            let isDiscount = rawAmount < .zero || isDiscountLine(lower)
            let amount     = isDiscount ? -abs(rawAmount) : rawAmount

            if lower.contains("total") && !lower.contains("sub") && !lower.contains("subtotal") {
                if let existing = total { total = max(existing, amount) } else { total = amount }
            } else if lower.contains("tax") || lower.contains("gst")
                        || lower.contains("hst") || lower.contains("vat") {
                tax = amount
            } else if lower.contains("tip") || lower.contains("gratuity")
                        || lower.contains("service charge") || lower.contains("svchrg") {
                tip = amount
            } else if lower.contains("subtotal") || lower.contains("sub total") {
                continue
            } else {
                var name = leftText.isEmpty ? stripPrice(from: fullText) : leftText
                name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty || name.count < 2 { continue }

                // A discount is always a single line worth its face value. Routing it through
                // `parseQuantity` would divide a negative by a parsed quantity for no benefit —
                // "2x" never appears on a voucher line — and risks turning £-2.00 into £-1.00.
                let (qty, unitPrice) = isDiscount
                    ? (1, amount)
                    : parseQuantity(from: name, totalPrice: amount)
                let cleanName        = stripQuantityPrefix(from: name)

                // Gap 7: collect alternate prices from OCR candidate strings for this row's
                // price column — used by the reconciliation pass if math doesn't close.
                let priceLines = rightLines.isEmpty ? row : rightLines
                let altPrices: [Decimal] = priceLines
                    .flatMap(\.alternates)
                    .compactMap { extractDecimal(from: $0) }
                    .filter { (isDiscount ? $0 < .zero : $0 > .zero) && $0 != amount }

                // The row's own OCR confidence, so the review screen can point at the lines that
                // were hardest to read. Uses the weakest line in the row: the price is what matters
                // and a confident item name does not vouch for a doubtful number beside it.
                var item = ReceiptItem(name: cleanName, quantity: qty, unitPrice: unitPrice)
                item.confidence = Double(row.map(\.confidence).min() ?? 1)
                parsedItems.append(ParsedItem(item: item, candidatePrices: altPrices))
            }
        }

        let receipt = Receipt(
            id:              UUID(),
            expenseID:       nil,
            imageURL:        nil,
            merchant:        merchant,
            items:           parsedItems.map(\.item),
            subtotal:        nil,
            tax:             tax,
            tip:             tip,
            total:           total,
            currency:        currency,
            transactionDate: nil,   // set by processScan after return
            scannedAt:       Date()
        )
        return (receipt, parsedItems)
    }

    // MARK: - Gap 7: Constraint-Solving Reconciliation

    /// Attempts to fix a maths mismatch by substituting alternate OCR price candidates.
    ///
    /// **The old `|delta| ≤ $2.00` cap was backwards.** Its stated reasoning — that a larger gap
    /// means a structural parse failure rather than a digit misread — is the opposite of how OCR
    /// errors behave: a single misread digit produces a *large* delta. `18.99`→`78.99` is $60, and
    /// even `4.99`→`1.99` is $3, already outside the cap. Small deltas come from rounding or a
    /// missed penny item, which alternates rarely fix. So the cap excluded exactly the cases this
    /// function exists to repair.
    ///
    /// The cap was also not protecting against cost: this is a **single-substitution** search,
    /// `O(items × alternates)`.
    ///
    /// What genuinely needs bounding is a *wrong* correction, and the guard for that is **not** a
    /// magnitude limit. A first attempt here used `|delta| ≤ total` and was wrong twice over: it
    /// rejected the very case above (a `78.99` misread against a true total of `21.99` is a $60
    /// gap that legitimately exceeds the bill), and since `delta = total − itemsSum` such a bound
    /// can never exceed `max(total, itemsSum)` anyway — it would have been a guard that never
    /// fires. A unit test caught it.
    ///
    /// The real protection is **uniqueness**: a substitution is applied only when exactly one
    /// closes the gap. If several different ones do, there is no evidence for choosing among them
    /// — the old code silently took the first it found, and guessing writes a wrong price into
    /// someone's split. Ambiguity now leaves the warning for the user to resolve. Coincidental
    /// closure on a structurally broken parse is what uniqueness screens out.
    @discardableResult
    func reconcile(candidates: inout [ParsedItem],
                           total: Decimal, tax: Decimal, tip: Decimal) -> Bool {
        let itemsSum = candidates.reduce(Decimal.zero) { $0 + $1.item.totalPrice }
        let delta    = total - (itemsSum + tax + tip)

        // Use literal Decimal values — Decimal(string:) depends on locale and may return nil.
        let smallThreshold: Decimal = Decimal(2) / Decimal(100)   // 0.02
        let absDelta = delta < 0 ? -delta : delta

        // Already balanced, or there is no meaningful total to reconcile against.
        guard absDelta > smallThreshold, total > .zero else { return false }

        // Collect *every* substitution that closes the gap rather than taking the first.
        var fixes: [(index: Int, price: Decimal)] = []
        for i in candidates.indices {
            let original = candidates[i].item
            for altPrice in candidates[i].candidatePrices {
                let altTotal = altPrice * Decimal(original.quantity)
                let newDelta = delta + original.totalPrice - altTotal
                var absNew   = newDelta < 0 ? -newDelta : newDelta
                var rounded  = Decimal()
                NSDecimalRound(&rounded, &absNew, 2, .bankers)
                if rounded <= smallThreshold {
                    fixes.append((i, altPrice))
                }
            }
        }

        // Distinct proposals only: the same item offered the same price twice is still one answer.
        var distinct: [(index: Int, price: Decimal)] = []
        for fix in fixes where !distinct.contains(where: { $0.index == fix.index && $0.price == fix.price }) {
            distinct.append(fix)
        }
        guard distinct.count == 1, let fix = distinct.first else { return false }

        let original = candidates[fix.index].item
        var corrected = ReceiptItem(id: original.id, name: original.name,
                                    quantity: original.quantity, unitPrice: fix.price)
        corrected.assignedUserIDs = original.assignedUserIDs
        corrected.confidence      = original.confidence
        candidates[fix.index].item = corrected
        return true
    }

    // MARK: - Heuristic Helpers

    private func isMetadata(_ lower: String) -> Bool {
        let metaKeywords = ["thank you", "receipt #", "order #", "table", "server",
                            "cashier", "store #", "phone:", "www.", ".com",
                            "cash tend", "change", "visa", "mastercard", "amex",
                            "points", "earned", "redeemed", "balance due"]
        return metaKeywords.contains { lower.contains($0) }
    }

    func parseQuantity(from text: String, totalPrice: Decimal) -> (Int, Decimal) {
        let patterns: [(String, NSRegularExpression?)] = [
            (#"^(\d+)\s*[xX@×]\s*"#,    try? NSRegularExpression(pattern: #"^(\d+)\s*[xX@×]\s*"#)),
            (#"^[Qq][Tt][Yy]\s*(\d+)"#, try? NSRegularExpression(pattern: #"^[Qq][Tt][Yy]\s*(\d+)"#)),
        ]
        for (_, regex) in patterns {
            guard let regex else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let qRange = Range(match.range(at: 1), in: text),
               let qty = Int(text[qRange]), qty > 1 {
                return (qty, totalPrice / Decimal(qty))
            }
        }
        return (1, totalPrice)
    }

    func stripQuantityPrefix(from text: String) -> String {
        // `[xX@×]` must match `parseQuantity`'s class exactly. The Tier-1 fix that added U+00D7
        // for European receipts ("2×1.99") extended the *parsing* regex and not this one, so the
        // quantity was read correctly and then left glued to the item name as "2×BURGER".
        let patterns = [#"^\d+\s*[xX@×]\s*"#, #"^[Qq][Tt][Yy]\s*\d+\s*"#]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range  = NSRange(text.startIndex..., in: text)
                let result = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
                if result != text { return result.trimmingCharacters(in: .whitespaces) }
            }
        }
        return text
    }

    func stripPrice(from text: String) -> String {
        // Character class kept identical to `extractDecimal`'s. When it was narrower, a yen or
        // won line had its digits stripped and the bare symbol left behind: "BURGER ¥".
        let pattern = #"[\$£€₹¥￥₩]?\s*\d{1,6}[.,]\d{2}\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    /// Extracts the rightmost money value on a line, **preserving its sign**.
    ///
    /// The sign matters: the previous pattern had no `-`, so a discount line reading `-2.00`
    /// extracted as `2.00`, passed the `amount > .zero` guard, and was added as a **+2.00 item**.
    /// A receipt with a £2 voucher therefore over-counted by £4 and produced a mismatch warning
    /// with no visible cause. Both a leading minus and the trailing-minus form some tills print
    /// (`2.00-`) are recognised, as is the Unicode minus `−` that OCR frequently returns for `-`.
    func extractDecimal(from string: String) -> Decimal? {
        // SCAN-09: the integer part is optional. Tills print sub-unit amounts without a leading
        // zero — CVS bottle deposits read `.05` — and requiring a digit before the separator made
        // them invisible, so those lines vanished from the receipt entirely.
        //
        // SCAN-10: two lookaheads keep a **rate** from being read as an amount.
        //   (?!\d)    a third decimal digit means this is not money in any currency xBill
        //             supports. Without it `8.875` yields `8.87`, and on `NY 8.875% TAX  .89`
        //             that was the *only* thing on the line the old pattern could match —
        //             SCAN-09 hid the real amount and SCAN-10 supplied a wrong one.
        //   (?!\s*%)  a rate printed to exactly two decimals is indistinguishable by digit count;
        //             only the percent sign gives it away. `7.00%` and `8.00 %` both occur.
        let pattern = #"([-−])?\s*[\$£€₹¥￥₩]?\s*((?:\d{1,6})?[.,]\d{2})(?!\d)(?!\s*%)\s*([-−])?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        // M-12: use lastMatch so that on lines like "2x BURGER 4.99 9.98" we
        // pick up the rightmost value (line total) instead of the unit price.
        let matches = regex.matches(in: string, range: range)
        guard let match = matches.last,
              let capRange = Range(match.range(at: 2), in: string) else { return nil }
        var raw = string[capRange].replacingOccurrences(of: ",", with: ".")
        // `Decimal(string:)` accepts ".05", but only because of a leading-zero convention that is
        // not worth depending on across locales — normalise it here instead.
        if raw.hasPrefix(".") { raw = "0" + raw }
        guard let value = Decimal(string: raw) else { return nil }

        let leading  = Range(match.range(at: 1), in: string).map { String(string[$0]) }
        let trailing = Range(match.range(at: 3), in: string).map { String(string[$0]) }
        let isNegative = leading != nil || trailing != nil
        return isNegative ? -value : value
    }

    /// Lines that reduce the bill rather than adding to it. Checked in addition to a parsed
    /// negative, because plenty of receipts print a discount as a positive number under a label.
    static let discountKeywords = [
        "discount", "coupon", "voucher", "promo", "savings", "saved",
        "off", "rebate", "credit", "refund", "adjustment"
    ]

    func isDiscountLine(_ lower: String) -> Bool {
        Self.discountKeywords.contains { lower.contains($0) }
    }

    // MARK: - Convert ParsedReceiptJSON → Receipt

    /// Converts a JSON amount to `Decimal` **without** inheriting the binary float's error.
    ///
    /// `Decimal(Double)` reproduces the float exactly as stored, so a receipt line of 4.99 becomes
    /// `4.990000000000001024`, 0.07 becomes `0.07000000000000001024`, and a 9.98 total becomes
    /// `9.980000000000002048`. Going through the shortest round-trip decimal string — which is
    /// what `String(Double)` produces — recovers the number the model actually meant.
    ///
    /// This is the only place money enters the app as a binary float: everywhere else the rule is
    /// `Decimal` end to end. The model returns JSON numbers, so the boundary is unavoidable; the
    /// error it introduces is not.
    static func money(_ value: Double) -> Decimal {
        Decimal(string: String(value)) ?? Decimal(value)
    }

    func convert(_ parsed: ParsedReceiptJSON) -> Receipt {
        let items = parsed.items.map { item in
            ReceiptItem(
                name:      item.name,
                quantity:  item.quantity,
                unitPrice: Self.money(item.unitPrice)
            )
        }
        return Receipt(
            id:              UUID(),
            expenseID:       nil,
            imageURL:        nil,
            merchant:        parsed.merchant,
            items:           items,
            subtotal:        parsed.subtotal.map { Self.money($0) },
            tax:             parsed.tax.map       { Self.money($0) },
            tip:             parsed.tip.map       { Self.money($0) },
            total:           parsed.total.map     { Self.money($0) },
            currency:        parsed.currency,
            transactionDate: nil,   // set by processScan after return
            scannedAt:       Date()
        )
    }

    // MARK: - Validation

    private func validate(_ receipt: Receipt, parsed: ParsedReceiptJSON) -> String? {
        guard let total = receipt.total else { return nil }
        let itemsSum = receipt.items.reduce(Decimal.zero) { $0 + $1.totalPrice }
        let expected = itemsSum + (receipt.tax ?? .zero) + (receipt.tip ?? .zero)
        var diff     = expected - total
        if diff < 0 { diff = -diff }
        var rounded  = Decimal()
        NSDecimalRound(&rounded, &diff, 2, .bankers)
        let smallThreshold: Decimal = Decimal(2) / Decimal(100)   // 0.02
        guard rounded > smallThreshold else { return nil }
        return "Total \(total.formatted(currencyCode: receipt.currency)) doesn't match items + tax + tip. Please review."
    }

    private func validateHeuristic(_ receipt: Receipt) -> String? {
        validate(receipt, parsed: ParsedReceiptJSON(
            merchant:        nil,
            items:           [],
            subtotal:        nil,
            tax:             receipt.tax.map   { NSDecimalNumber(decimal: $0).doubleValue },
            tip:             receipt.tip.map   { NSDecimalNumber(decimal: $0).doubleValue },
            total:           receipt.total.map { NSDecimalNumber(decimal: $0).doubleValue },
            currency:        receipt.currency,
            confidence:      0,
            transactionDate: nil
        ))
    }
}

// MARK: - L-12: CGImagePropertyOrientation from UIImage.Orientation

/// Maps UIImage.Orientation (EXIF-based) to the CGImagePropertyOrientation values
/// expected by VNImageRequestHandler so Vision interprets rotated receipts correctly.
private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up:            self = .up
        case .upMirrored:    self = .upMirrored
        case .down:          self = .down
        case .downMirrored:  self = .downMirrored
        case .left:          self = .left
        case .leftMirrored:  self = .leftMirrored
        case .right:         self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}

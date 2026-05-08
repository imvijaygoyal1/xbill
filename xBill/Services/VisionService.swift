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
private struct ParsedItem: Sendable {
    var item:            ReceiptItem
    var candidatePrices: [Decimal]
}

// MARK: - VisionService

final class VisionService: Sendable {
    static let shared = VisionService()
    private init() {}

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
        var mutableCandidates = candidates
        let warning: String?
        if let total = receipt.total,
           validateHeuristic(receipt) != nil,
           reconcile(candidates: &mutableCandidates, total: total,
                     tax: receipt.tax ?? .zero, tip: receipt.tip ?? .zero) {
            receipt.items = mutableCandidates.map(\.item)
            warning = nil
        } else {
            warning = validateHeuristic(receipt)
        }

        let category = suggestCategory(merchant: receipt.merchant, items: receipt.items)
        return ScanResult(
            receipt:           receipt,
            confidence:        warning == nil ? 0.75 : 0.55,
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
        let context = CIContext(options: [.useSoftwareRenderer: false])

        // Exposure: average luminance < 12% → too dark for OCR
        if let luminance = averageLuminance(ciImage, context: context), luminance < 0.12 {
            throw AppError.validationFailed("Image is too dark — move to better lighting and try again.")
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

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let outputCG = context.createCGImage(current, from: current.extent) else { return image }
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

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
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

    private func groupIntoRows(_ lines: [OCRLine], threshold: CGFloat = 0.025) -> [[OCRLine]] {
        var sorted = lines.sorted { $0.midY < $1.midY }
        var rows: [[OCRLine]] = []

        while !sorted.isEmpty {
            let anchor = sorted.removeFirst()
            var row    = [anchor]
            sorted     = sorted.filter { line in
                if abs(line.midY - anchor.midY) <= threshold {
                    row.append(line)
                    return false
                }
                return true
            }
            rows.append(row.sorted { $0.midX < $1.midX })
        }
        return rows
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
    private func extractTransactionDate(from text: String) -> Date? {
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
    private func suggestCategory(merchant: String?, items: [ReceiptItem]) -> Expense.Category? {
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

    private func parseWithHeuristics(rows: [[OCRLine]]) -> (receipt: Receipt, candidates: [ParsedItem]) {
        var parsedItems: [ParsedItem] = []
        var total:    Decimal?
        var tax:      Decimal?
        var tip:      Decimal?
        var merchant: String?
        var currency  = "USD"

        // First non-trivial row → merchant name
        if let firstRow = rows.first {
            merchant = firstRow.map(\.text).joined(separator: " ")
        }

        // Currency from any symbol found anywhere in the text
        let allText = rows.flatMap { $0 }.map(\.text).joined()
        if allText.contains("£")      { currency = "GBP" }
        else if allText.contains("€") { currency = "EUR" }
        else if allText.contains("₹") { currency = "INR" }

        for row in rows.dropFirst() {
            let fullText = row.map(\.text).joined(separator: " ")
            let lower    = fullText.lowercased()

            if isMetadata(lower) { continue }

            let leftLines   = row.filter { $0.midX < 0.55 }
            let rightLines  = row.filter { $0.midX >= 0.55 }
            let leftText    = leftLines.map(\.text).joined(separator: " ")
            let rightText   = rightLines.map(\.text).joined(separator: " ")
            let priceSource = rightText.isEmpty ? fullText : rightText

            guard let amount = extractDecimal(from: priceSource), amount > .zero else { continue }

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

                let (qty, unitPrice) = parseQuantity(from: name, totalPrice: amount)
                let cleanName        = stripQuantityPrefix(from: name)

                // Gap 7: collect alternate prices from OCR candidate strings for this row's
                // price column — used by the reconciliation pass if math doesn't close.
                let priceLines = rightLines.isEmpty ? row : rightLines
                let altPrices: [Decimal] = priceLines
                    .flatMap(\.alternates)
                    .compactMap { extractDecimal(from: $0) }
                    .filter { $0 > .zero && $0 != amount }

                let item = ReceiptItem(name: cleanName, quantity: qty, unitPrice: unitPrice)
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

    /// Attempts to fix a math mismatch by substituting alternate OCR price candidates.
    /// Only tries when `|delta| ≤ $2.00` — larger gaps indicate a structural parse failure,
    /// not a single-digit OCR misread. Returns `true` and mutates `candidates` on success.
    @discardableResult
    private func reconcile(candidates: inout [ParsedItem],
                           total: Decimal, tax: Decimal, tip: Decimal) -> Bool {
        let itemsSum = candidates.reduce(Decimal.zero) { $0 + $1.item.totalPrice }
        let delta    = total - (itemsSum + tax + tip)

        // Skip if delta is trivially small (already passes) or too large to be a digit error.
        // Use literal Decimal values — Decimal(string:) depends on locale and may return nil.
        let smallThreshold: Decimal = Decimal(2) / Decimal(100)   // 0.02
        let largeThreshold: Decimal = Decimal(2)                   // 2.00
        let absDelta = delta < 0 ? -delta : delta
        guard absDelta > smallThreshold,
              absDelta <= largeThreshold else { return false }

        for i in candidates.indices {
            let original = candidates[i].item
            for altPrice in candidates[i].candidatePrices {
                let altTotal  = altPrice * Decimal(original.quantity)
                // New delta if we swap this item's price
                let newDelta  = delta + original.totalPrice - altTotal
                var absNew    = newDelta < 0 ? -newDelta : newDelta
                var rounded   = Decimal()
                NSDecimalRound(&rounded, &absNew, 2, .bankers)
                if rounded <= smallThreshold {
                    var corrected = ReceiptItem(id: original.id, name: original.name,
                                               quantity: original.quantity, unitPrice: altPrice)
                    corrected.assignedUserIDs = original.assignedUserIDs
                    candidates[i].item = corrected
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Heuristic Helpers

    private func isMetadata(_ lower: String) -> Bool {
        let metaKeywords = ["thank you", "receipt #", "order #", "table", "server",
                            "cashier", "store #", "phone:", "www.", ".com",
                            "cash tend", "change", "visa", "mastercard", "amex",
                            "points", "earned", "redeemed", "balance due"]
        return metaKeywords.contains { lower.contains($0) }
    }

    private func parseQuantity(from text: String, totalPrice: Decimal) -> (Int, Decimal) {
        let patterns: [(String, NSRegularExpression?)] = [
            (#"^(\d+)\s*[xX@]\s*"#,    try? NSRegularExpression(pattern: #"^(\d+)\s*[xX@]\s*"#)),
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

    private func stripQuantityPrefix(from text: String) -> String {
        let patterns = [#"^\d+\s*[xX@]\s*"#, #"^[Qq][Tt][Yy]\s*\d+\s*"#]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range  = NSRange(text.startIndex..., in: text)
                let result = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
                if result != text { return result.trimmingCharacters(in: .whitespaces) }
            }
        }
        return text
    }

    private func stripPrice(from text: String) -> String {
        let pattern = #"[\$£€₹]?\s*\d{1,6}[.,]\d{2}\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private func extractDecimal(from string: String) -> Decimal? {
        let pattern = #"[\$£€₹]?\s*(\d{1,6}[.,]\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              let capRange = Range(match.range(at: 1), in: string) else { return nil }
        let raw = string[capRange].replacingOccurrences(of: ",", with: ".")
        return Decimal(string: raw)
    }

    // MARK: - Convert ParsedReceiptJSON → Receipt

    private func convert(_ parsed: ParsedReceiptJSON) -> Receipt {
        let items = parsed.items.map { item in
            ReceiptItem(
                name:      item.name,
                quantity:  item.quantity,
                unitPrice: Decimal(item.unitPrice)
            )
        }
        return Receipt(
            id:              UUID(),
            expenseID:       nil,
            imageURL:        nil,
            merchant:        parsed.merchant,
            items:           items,
            subtotal:        parsed.subtotal.map { Decimal($0) },
            tax:             parsed.tax.map       { Decimal($0) },
            tip:             parsed.tip.map       { Decimal($0) },
            total:           parsed.total.map     { Decimal($0) },
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

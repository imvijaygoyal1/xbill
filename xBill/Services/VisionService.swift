//
//  VisionService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Vision
import UIKit

// MARK: - OCRLine

/// A single block of text extracted from Vision, with its normalized position.
struct OCRLine: Sendable {
    let text:       String
    let midX:       CGFloat   // 0 = left edge, 1 = right edge
    let midY:       CGFloat   // 0 = top of image, 1 = bottom (Y-flipped from Vision)
    let confidence: Float
}

// MARK: - ScanResult

struct ScanResult: Sendable {
    let receipt:           Receipt
    let confidence:        Double
    let tier:              String    // "Apple Intelligence" or "Heuristic"
    let validationWarning: String?
}

// MARK: - VisionService

final class VisionService: Sendable {
    static let shared = VisionService()
    private init() {}

    // MARK: - Public Entry Point

    func scanReceipt(from image: UIImage) async throws -> ScanResult {
        let ocrLines  = try await recognizeText(in: image)
        let rows      = groupIntoRows(ocrLines)
        let ocrText   = rows.map { $0.map(\.text).joined(separator: " ") }.joined(separator: "\n")

        // Tier 1 — Apple Foundation Models (iOS 18.1+, Apple Intelligence device)
        if #available(iOS 26.0, *) {
            let fm = FoundationModelService.shared
            if fm.isAvailable {
                do {
                    let parsed  = try await fm.parseReceipt(ocrText: ocrText)
                    let receipt = convert(parsed)
                    let warning = validate(receipt, parsed: parsed)
                    return ScanResult(
                        receipt:           receipt,
                        confidence:        parsed.confidence,
                        tier:              "Apple Intelligence",
                        validationWarning: warning
                    )
                } catch {
                    // Fall through to heuristics
                }
            }
        }

        // Tier 2 — Improved heuristics (all devices, iOS 17+)
        let receipt = parseWithHeuristics(rows: rows)
        let warning = validateHeuristic(receipt)
        return ScanResult(
            receipt:           receipt,
            confidence:        warning == nil ? 0.75 : 0.55,
            tier:              "Heuristic",
            validationWarning: warning
        )
    }

    // MARK: - OCR with Bounding Boxes

    private func recognizeText(in image: UIImage) async throws -> [OCRLine] {
        guard let cgImage = image.cgImage else {
            throw AppError.validationFailed("Cannot process image — invalid format.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: AppError.from(error))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines: [OCRLine] = observations.compactMap { obs in
                    guard let candidate = obs.topCandidates(1).first,
                          !candidate.string.trimmingCharacters(in: .whitespaces).isEmpty
                    else { return nil }
                    // Vision bounding box: origin is bottom-left; flip Y for top-down reading order
                    return OCRLine(
                        text:       candidate.string,
                        midX:       obs.boundingBox.midX,
                        midY:       1 - obs.boundingBox.midY,
                        confidence: candidate.confidence
                    )
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel    = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: AppError.from(error))
            }
        }
    }

    // MARK: - Spatial Grouping

    /// Groups OCR lines that share approximately the same vertical position into rows,
    /// then sorts each row left-to-right. Threshold ≈ 2.5% of image height.
    private func groupIntoRows(_ lines: [OCRLine], threshold: CGFloat = 0.025) -> [[OCRLine]] {
        var sorted    = lines.sorted { $0.midY < $1.midY }
        var rows:     [[OCRLine]] = []

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

    // MARK: - Tier 2: Improved Heuristics

    private func parseWithHeuristics(rows: [[OCRLine]]) -> Receipt {
        var items:    [ReceiptItem] = []
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

            // Skip metadata lines
            if isMetadata(lower) { continue }

            // Split row into left column (name) and right column (price)
            let leftText  = row.filter { $0.midX < 0.55 }.map(\.text).joined(separator: " ")
            let rightText = row.filter { $0.midX >= 0.55 }.map(\.text).joined(separator: " ")
            let priceSource = rightText.isEmpty ? fullText : rightText

            guard let amount = extractDecimal(from: priceSource), amount > .zero else { continue }

            if lower.contains("total") && !lower.contains("sub") && !lower.contains("subtotal") {
                // Prefer larger total value (handles "TOTAL" before "GRAND TOTAL")
                if let existing = total { total = max(existing, amount) } else { total = amount }
            } else if lower.contains("tax") || lower.contains("gst")
                        || lower.contains("hst") || lower.contains("vat") {
                tax = amount
            } else if lower.contains("tip") || lower.contains("gratuity")
                        || lower.contains("service charge") || lower.contains("svchrg") {
                tip = amount
            } else if lower.contains("subtotal") || lower.contains("sub total") {
                // Skip — subtotal is not an item
                continue
            } else {
                // Line item — use left column as name; if empty fall back to full line minus price
                var name = leftText.isEmpty ? stripPrice(from: fullText) : leftText
                name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty || name.count < 2 { continue }

                // Detect quantity prefix: "2x", "2 @", "QTY 2"
                let (qty, unitPrice) = parseQuantity(from: name, totalPrice: amount)
                let cleanName        = stripQuantityPrefix(from: name)
                items.append(ReceiptItem(name: cleanName, quantity: qty, unitPrice: unitPrice))
            }
        }

        return Receipt(
            id:        UUID(),
            expenseID: nil,
            imageURL:  nil,
            merchant:  merchant,
            items:     items,
            subtotal:  nil,
            tax:       tax,
            tip:       tip,
            total:     total,
            currency:  currency,
            scannedAt: Date()
        )
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
                let unit = totalPrice / Decimal(qty)
                return (qty, unit)
            }
        }
        return (1, totalPrice)
    }

    private func stripQuantityPrefix(from text: String) -> String {
        let patterns = [#"^\d+\s*[xX@]\s*"#, #"^[Qq][Tt][Yy]\s*\d+\s*"#]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..., in: text)
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
            id:        UUID(),
            expenseID: nil,
            imageURL:  nil,
            merchant:  parsed.merchant,
            items:     items,
            subtotal:  parsed.subtotal.map { Decimal($0) },
            tax:       parsed.tax.map       { Decimal($0) },
            tip:       parsed.tip.map       { Decimal($0) },
            total:     parsed.total.map     { Decimal($0) },
            currency:  parsed.currency,
            scannedAt: Date()
        )
    }

    // MARK: - Validation

    /// Validates that items + tax + tip ≈ total. Returns a warning string if mismatch > $0.02.
    private func validate(_ receipt: Receipt, parsed: ParsedReceiptJSON) -> String? {
        guard let total = receipt.total else { return nil }
        let itemsSum = receipt.items.reduce(Decimal.zero) { $0 + $1.totalPrice }
        let expected = itemsSum + (receipt.tax ?? .zero) + (receipt.tip ?? .zero)
        var diff     = expected - total
        if diff < 0 { diff = -diff }
        var rounded  = Decimal()
        NSDecimalRound(&rounded, &diff, 2, .bankers)
        guard rounded > Decimal(string: "0.02")! else { return nil }
        return "Total \(total.formatted(currencyCode: receipt.currency)) doesn't match items + tax + tip. Please review."
    }

    private func validateHeuristic(_ receipt: Receipt) -> String? {
        validate(receipt, parsed: ParsedReceiptJSON(
            merchant: nil, items: [], subtotal: nil,
            tax:      receipt.tax.map    { NSDecimalNumber(decimal: $0).doubleValue },
            tip:      receipt.tip.map    { NSDecimalNumber(decimal: $0).doubleValue },
            total:    receipt.total.map  { NSDecimalNumber(decimal: $0).doubleValue },
            currency: receipt.currency, confidence: 0
        ))
    }
}

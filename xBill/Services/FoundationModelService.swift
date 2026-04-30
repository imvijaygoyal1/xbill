//
//  FoundationModelService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - FoundationModelService
// Uses Apple's on-device language model (Apple Intelligence) to parse
// receipt OCR text into structured output. Free, private, no API key.
// Requires iOS 26.0+ on an Apple Intelligence capable device.

@available(iOS 26.0, *)
final class FoundationModelService: Sendable {
    static let shared = FoundationModelService()
    private init() {}

    // MARK: - Availability

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.isAvailable
        #else
        return false
        #endif
    }

    // MARK: - Parse

    func parseReceipt(ocrText: String) async throws -> ParsedReceiptJSON {
        // Reject low-quality OCR before hitting the model
        let lineCount = ocrText.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        guard lineCount >= 3 else {
            throw AppError.validationFailed("Too little text detected — scan quality too low for AI parsing.")
        }

        #if canImport(FoundationModels)
        return try await parseWithStructuredOutput(ocrText: ocrText)
        #else
        throw AppError.unknown("FoundationModels not available on this platform.")
        #endif
    }

    // MARK: - Structured Output (iOS 26+ @Generable)

    #if canImport(FoundationModels)
    private func parseWithStructuredOutput(ocrText: String) async throws -> ParsedReceiptJSON {
        let instructions = """
        You are a receipt data extractor. Given raw OCR text from a receipt, extract structured data.

        Rules:
        - items: purchasable line items only (name + price). Skip: payment methods, loyalty points, receipt numbers, addresses, dates, "THANK YOU", server names.
        - quantity: if a line says "2x", "2 @", or "QTY 2", set quantity; unit_price = total_price / quantity.
        - tax: lines with TAX, GST, HST, VAT.
        - tip: lines with TIP, GRATUITY, SERVICE CHARGE.
        - total: final charged amount — prefer GRAND TOTAL or TOTAL DUE over plain TOTAL.
        - currency: infer from symbol ($=USD, £=GBP, €=EUR, ₹=INR, ¥=JPY). Default USD.
        - confidence: 0.0–1.0, lower if ambiguous or items don't sum to total.
        """
        let session  = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: ocrText, generating: ReceiptGenerable.self)
        let g        = response.content
        return ParsedReceiptJSON(
            merchant:   g.merchant,
            items:      g.items.map { ParsedItemJSON(name: $0.name, quantity: $0.quantity,
                                                      unitPrice: $0.unitPrice, totalPrice: $0.totalPrice) },
            subtotal:   g.subtotal,
            tax:        g.tax,
            tip:        g.tip,
            total:      g.total,
            currency:   g.currency.isEmpty ? "USD" : g.currency,
            confidence: g.confidence
        )
    }
    #endif
}

// MARK: - @Generable types (structured output schema for Foundation Models)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct ReceiptGenerable {
    var merchant:   String?
    var items:      [ItemGenerable]
    var subtotal:   Double?
    var tax:        Double?
    var tip:        Double?
    var total:      Double?
    var currency:   String
    var confidence: Double
}

@available(iOS 26.0, *)
@Generable
private struct ItemGenerable {
    var name:       String
    var quantity:   Int
    var unitPrice:  Double
    var totalPrice: Double
}
#endif

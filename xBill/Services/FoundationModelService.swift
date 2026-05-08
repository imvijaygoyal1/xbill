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

    // MARK: - Session cache

    // A single LanguageModelSession is reused across parseReceipt calls.
    // LanguageModelSession creation is expensive; recreating it on every call
    // adds latency with no benefit because the session holds only instruction state.
    // nonisolated(unsafe) is safe here: the session is effectively read-only after
    // its first lazy creation (the setter in the stored property is the only writer,
    // called once under normal usage patterns).
    #if canImport(FoundationModels)
    nonisolated(unsafe) private var _cachedSession: LanguageModelSession?
    #endif

    // MARK: - Parse

    /// `language`: BCP-47 tag from NLLanguageRecognizer (e.g. "fr", "de") — improves
    /// accuracy for non-English receipts by giving the model cultural context.
    func parseReceipt(ocrText: String, language: String? = nil) async throws -> ParsedReceiptJSON {
        let lineCount = ocrText.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        guard lineCount >= 3 else {
            throw AppError.validationFailed("Too little text detected — scan quality too low for AI parsing.")
        }

        #if canImport(FoundationModels)
        return try await parseWithStructuredOutput(ocrText: ocrText, language: language)
        #else
        throw AppError.unknown("FoundationModels not available on this platform.")
        #endif
    }

    // MARK: - Structured Output (iOS 26+ @Generable)

    #if canImport(FoundationModels)
    private func parseWithStructuredOutput(ocrText: String, language: String?) async throws -> ParsedReceiptJSON {
        let langNote = language.map { "The receipt is in locale '\($0)'. Use that locale's conventions for number formats and currency." } ?? ""
        let instructions = """
        You are a receipt data extractor. Given raw OCR text from a receipt, extract structured data.
        \(langNote)

        Rules:
        - items: purchasable line items only (name + price). Skip: payment methods, loyalty points, receipt numbers, addresses, "THANK YOU", server names.
        - quantity: if a line says "2x", "2 @", or "QTY 2", set quantity; unit_price = total_price / quantity.
        - tax: lines with TAX, GST, HST, VAT.
        - tip: lines with TIP, GRATUITY, SERVICE CHARGE.
        - total: final charged amount — prefer GRAND TOTAL or TOTAL DUE over plain TOTAL.
        - currency: infer from symbol ($=USD, £=GBP, €=EUR, ₹=INR, ¥=JPY). Default USD.
        - transaction_date: the date printed on the receipt in "YYYY-MM-DD" format. Use nil if not found.
        - confidence: 0.0–1.0, lower if ambiguous or items don't sum to total.
        """
        // Reuse a cached session; create it lazily on first call.
        if _cachedSession == nil {
            _cachedSession = LanguageModelSession(instructions: instructions)
        }
        let session = _cachedSession!
        let response = try await session.respond(to: ocrText, generating: ReceiptGenerable.self)
        let g        = response.content
        return ParsedReceiptJSON(
            merchant:        g.merchant,
            items:           g.items.map { ParsedItemJSON(name: $0.name, quantity: $0.quantity,
                                                          unitPrice: $0.unitPrice, totalPrice: $0.totalPrice) },
            subtotal:        g.subtotal,
            tax:             g.tax,
            tip:             g.tip,
            total:           g.total,
            currency:        g.currency.isEmpty ? "USD" : g.currency,
            confidence:      g.confidence,
            transactionDate: g.transactionDate
        )
    }
    #endif
}

// MARK: - @Generable types (structured output schema for Foundation Models)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct ReceiptGenerable {
    var merchant:        String?
    var items:           [ItemGenerable]
    var subtotal:        Double?
    var tax:             Double?
    var tip:             Double?
    var total:           Double?
    var currency:        String
    var confidence:      Double
    var transactionDate: String?
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

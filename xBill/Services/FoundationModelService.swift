import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - FoundationModelService
// Uses Apple's on-device language model (Apple Intelligence) to parse
// receipt OCR text into structured JSON. Free, private, no API key needed.
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
        #if canImport(FoundationModels)
        let instructions = """
        You are a receipt data extractor. Given raw OCR text from a receipt, \
        extract structured data and return ONLY valid JSON — no markdown, no explanation.

        Rules:
        - items: include only purchasable line items with a name and price.
          Skip: payment methods (CASH, VISA), loyalty points, receipt numbers, \
          addresses, dates, "THANK YOU", order numbers, server names.
        - quantity: if a line says "2x", "2 @", or "QTY 2", set quantity; \
          unit_price = total_price / quantity.
        - subtotal: sum of items before tax and tip.
        - tax: lines with TAX, GST, HST, VAT.
        - tip: lines with TIP, GRATUITY, SERVICE CHARGE, SVCHRG.
        - total: final charged amount — prefer TOTAL DUE or GRAND TOTAL over SUBTOTAL.
        - currency: infer from symbol ($=USD, £=GBP, €=EUR, ₹=INR). Default USD.
        - confidence: 0.0–1.0, lower if text is ambiguous or items don't sum to total.

        JSON schema (use null for unknown; never omit keys):
        {"merchant":<string|null>,"items":[{"name":<string>,"quantity":<int>,"unit_price":<number>,"total_price":<number>}],"subtotal":<number|null>,"tax":<number|null>,"tip":<number|null>,"total":<number|null>,"currency":<string>,"confidence":<number>}
        """
        let session  = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: ocrText)
        return try decodeJSON(from: response.content)
        #else
        throw AppError.unknown("FoundationModels not available on this platform.")
        #endif
    }

    // MARK: - JSON Decoding

    private func decodeJSON(from text: String) throws -> ParsedReceiptJSON {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = cleaned.data(using: .utf8) else {
            throw AppError.unknown("Could not encode model response as UTF-8.")
        }
        do {
            return try JSONDecoder().decode(ParsedReceiptJSON.self, from: data)
        } catch {
            throw AppError.serverError("Receipt parsing failed — model returned unexpected format.")
        }
    }
}

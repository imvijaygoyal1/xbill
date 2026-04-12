import Foundation

// MARK: - ParsedReceiptJSON
// Decodable struct matching the JSON schema produced by
// FoundationModelService (Tier 1) and returned by heuristic parser (Tier 2).

struct ParsedReceiptJSON: Decodable, Sendable {
    let merchant:   String?
    let items:      [ParsedItemJSON]
    let subtotal:   Double?
    let tax:        Double?
    let tip:        Double?
    let total:      Double?
    let currency:   String
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case merchant, items, subtotal, tax, tip, total, currency, confidence
    }
}

struct ParsedItemJSON: Decodable, Sendable {
    let name:       String
    let quantity:   Int
    let unitPrice:  Double
    let totalPrice: Double

    enum CodingKeys: String, CodingKey {
        case name, quantity
        case unitPrice  = "unit_price"
        case totalPrice = "total_price"
    }
}

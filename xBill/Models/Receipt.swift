import Foundation

// MARK: - Receipt

struct Receipt: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var expenseID: UUID?
    var imageURL: URL?
    var merchant: String?
    var items: [ReceiptItem]
    var subtotal: Decimal?
    var tax: Decimal?
    var tip: Decimal?
    var total: Decimal?
    var currency: String
    var scannedAt: Date

    var computedTotal: Decimal {
        (subtotal ?? .zero) + (tax ?? .zero) + (tip ?? .zero)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case expenseID = "expense_id"
        case imageURL  = "image_url"
        case merchant
        case items
        case subtotal
        case tax
        case tip
        case total
        case currency
        case scannedAt = "scanned_at"
    }
}

// MARK: - ReceiptItem

struct ReceiptItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var quantity: Int
    var unitPrice: Decimal
    var assignedUserIDs: [UUID]

    var totalPrice: Decimal { unitPrice * Decimal(quantity) }

    init(id: UUID = UUID(), name: String, quantity: Int = 1, unitPrice: Decimal) {
        self.id              = id
        self.name            = name
        self.quantity        = quantity
        self.unitPrice       = unitPrice
        self.assignedUserIDs = []
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case quantity
        case unitPrice         = "unit_price"
        case assignedUserIDs   = "assigned_user_ids"
    }
}

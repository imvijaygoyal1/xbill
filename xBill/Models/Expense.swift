import Foundation

// MARK: - Expense

struct Expense: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let groupID: UUID
    var title: String
    var amount: Decimal
    var currency: String
    let payerID: UUID
    var category: Category
    var notes: String?
    var receiptURL: URL?
    let createdAt: Date

    enum Category: String, Codable, CaseIterable, Sendable {
        case food          = "food"
        case transport     = "transport"
        case accommodation = "accommodation"
        case entertainment = "entertainment"
        case utilities     = "utilities"
        case shopping      = "shopping"
        case health        = "health"
        case other         = "other"

        var displayName: String {
            switch self {
            case .food:          return "Food & Drink"
            case .transport:     return "Transport"
            case .accommodation: return "Accommodation"
            case .entertainment: return "Entertainment"
            case .utilities:     return "Utilities"
            case .shopping:      return "Shopping"
            case .health:        return "Health"
            case .other:         return "Other"
            }
        }

        var systemImage: String {
            switch self {
            case .food:          return "fork.knife"
            case .transport:     return "car.fill"
            case .accommodation: return "house.fill"
            case .entertainment: return "film.fill"
            case .utilities:     return "bolt.fill"
            case .shopping:      return "bag.fill"
            case .health:        return "heart.fill"
            case .other:         return "ellipsis.circle.fill"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case groupID    = "group_id"
        case title
        case amount
        case currency
        case payerID    = "paid_by"
        case category
        case notes
        case receiptURL = "receipt_url"
        case createdAt  = "created_at"
    }
}

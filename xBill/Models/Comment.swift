import Foundation

struct Comment: Codable, Identifiable, Sendable {
    let id: UUID
    let expenseID: UUID
    let userID: UUID
    var text: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case expenseID = "expense_id"
        case userID    = "user_id"
        case text
        case createdAt = "created_at"
    }
}

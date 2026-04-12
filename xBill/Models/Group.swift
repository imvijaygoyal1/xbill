import Foundation

// MARK: - BillGroup
// Matches public.groups schema exactly.

struct BillGroup: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    var emoji: String
    let createdBy: UUID
    var isArchived: Bool
    var currency: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, currency
        case createdBy  = "created_by"
        case isArchived = "is_archived"
        case createdAt  = "created_at"
    }
}

// MARK: - GroupMember
// Matches public.group_members schema (composite PK, no id/role columns).

struct GroupMember: Codable, Sendable {
    let groupId: UUID
    let userId: UUID
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case groupId  = "group_id"
        case userId   = "user_id"
        case joinedAt = "joined_at"
    }
}

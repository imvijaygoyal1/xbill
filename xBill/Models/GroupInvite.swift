import Foundation

struct GroupInvite: Codable, Identifiable, Sendable {
    let token: String
    let groupID: UUID
    let createdBy: UUID
    let expiresAt: Date

    var id: String { token }

    var inviteURL: URL? {
        URL(string: "xbill://join/\(token)")
    }

    enum CodingKeys: String, CodingKey {
        case token
        case groupID   = "group_id"
        case createdBy = "created_by"
        case expiresAt = "expires_at"
    }
}

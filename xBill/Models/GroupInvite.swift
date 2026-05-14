//
//  GroupInvite.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

// MARK: - InviteJoinRequest
// L-29: Moved here from AuthViewModel.swift — logically belongs alongside GroupInvite
// since both types represent the group-invite flow.

struct InviteJoinRequest: Identifiable, Sendable {
    let id = UUID()
    let token: String
}

// MARK: - GroupInvite

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

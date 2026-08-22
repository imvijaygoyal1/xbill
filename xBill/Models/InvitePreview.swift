//
//  InvitePreview.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  The group's public face, as shown on the join screen to someone who is not yet a member.
//
//  This is deliberately NOT `BillGroup`. An invitee cannot read the `groups` row — RLS restricts
//  it to members and the creator — so modelling the preview as a full group would imply access
//  the caller does not have. It carries only what the join screen renders.
//

import Foundation

struct InvitePreview: Decodable, Sendable {
    let groupID: UUID
    let name: String
    let emoji: String?
    let currency: String
    let memberCount: Int
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case groupID     = "group_id"
        case name
        case emoji
        case currency
        case memberCount = "member_count"
        case expiresAt   = "expires_at"
    }

    var displayEmoji: String { (emoji?.isEmpty == false ? emoji : nil) ?? "👥" }

    var memberSummary: String {
        memberCount == 1 ? "1 member" : "\(memberCount) members"
    }
}

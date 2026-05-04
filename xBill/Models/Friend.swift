//
//  Friend.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

// MARK: - FriendStatus

enum FriendStatus: String, Codable, Sendable {
    case pending
    case accepted
    case blocked
}

// MARK: - Friend

/// Mirrors the public.friends table row.
/// requester_id = who sent the request; addressee_id = who received it.
struct Friend: Codable, Identifiable, Sendable {
    let id:           UUID
    let requesterID:  UUID
    let addresseeID:  UUID
    let status:       FriendStatus
    let createdAt:    Date

    enum CodingKeys: String, CodingKey {
        case id
        case requesterID = "requester_id"
        case addresseeID = "addressee_id"
        case status
        case createdAt   = "created_at"
    }
}

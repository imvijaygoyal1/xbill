//
//  User.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

// MARK: - User
// Matches public.profiles schema exactly.

struct User: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let email: String
    var displayName: String
    var avatarURL: URL?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email
        case displayName = "display_name"
        case avatarURL   = "avatar_url"
        case createdAt   = "created_at"
    }
}

// MARK: - UserBalance

struct UserBalance: Identifiable, Equatable, Sendable {
    var id: UUID { userID }
    let userID: UUID
    let displayName: String
    let avatarURL: URL?
    /// Positive = owed money, Negative = owes money
    var netBalance: Decimal
    var currency: String
}

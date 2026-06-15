//
//  User.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

// MARK: - User
// Matches the public.profiles payload used by the app.

struct User: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let email: String
    var displayName: String
    var avatarURL: URL?
    var venmoHandle: String?
    var paypalHandle: String?
    var isActive: Bool
    let createdAt: Date

    var paypalEmail: String? {
        get { paypalHandle }
        set { paypalHandle = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case id, email
        case displayName  = "display_name"
        case avatarURL    = "avatar_url"
        case venmoHandle  = "venmo_handle"
        case paypalHandle = "paypal_handle"
        case paypalEmail  = "paypal_email"
        case isActive     = "is_active"
        case createdAt    = "created_at"
    }

    init(
        id: UUID,
        email: String,
        displayName: String,
        avatarURL: URL?,
        venmoHandle: String? = nil,
        paypalEmail: String? = nil,
        isActive: Bool = true,
        createdAt: Date
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.venmoHandle = venmoHandle
        self.paypalHandle = paypalEmail
        self.isActive = isActive
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        email = (try? container.decode(String.self, forKey: .email)) ?? ""
        displayName = try container.decode(String.self, forKey: .displayName)
        avatarURL = try? container.decodeIfPresent(URL.self, forKey: .avatarURL)
        venmoHandle = try? container.decodeIfPresent(String.self, forKey: .venmoHandle)
        paypalHandle = (try? container.decodeIfPresent(String.self, forKey: .paypalHandle))
            ?? (try? container.decodeIfPresent(String.self, forKey: .paypalEmail))
        isActive = (try? container.decode(Bool.self, forKey: .isActive)) ?? true
        createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(email, forKey: .email)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try container.encodeIfPresent(venmoHandle, forKey: .venmoHandle)
        try container.encodeIfPresent(paypalHandle, forKey: .paypalHandle)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdAt, forKey: .createdAt)
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

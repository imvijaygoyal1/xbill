//
//  Settlement.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

// MARK: - Settlement

struct Settlement: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let groupID: UUID
    let fromUserID: UUID
    let toUserID: UUID
    var amount: Decimal
    var currency: String
    var paymentLink: URL?
    var method: PaymentMethod
    let createdAt: Date
    var settledAt: Date?
    var isSettled: Bool

    enum PaymentMethod: String, Codable, Sendable {
        case cash       = "cash"
        case upi        = "upi"
        case paypal     = "paypal"
        case venmo      = "venmo"
        case bankTransfer = "bank_transfer"
        case other      = "other"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case groupID    = "group_id"
        case fromUserID = "from_user_id"
        case toUserID   = "to_user_id"
        case amount
        case currency
        case paymentLink = "payment_link"
        case method
        case createdAt  = "created_at"
        case settledAt  = "settled_at"
        case isSettled  = "is_settled"
    }
}

// MARK: - SettlementSuggestion

/// Represents who should pay whom, derived from SplitCalculator.
struct SettlementSuggestion: Identifiable, Equatable, Sendable {
    let id: UUID
    let fromUserID: UUID
    let fromName: String
    let toUserID: UUID
    let toName: String
    var amount: Decimal
    var currency: String
}

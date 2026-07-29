//
//  Settlement.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

// MARK: - Settlement

/// One recorded payment. The ledger row that balances are derived from.
///
/// Replaces the old `splits.is_settled` flag: a payment is an amount from one person to
/// another, not a mutation of individual expense shares. See
/// `docs/superpowers/specs/2026-07-28-settlements-ledger-design.md`.
struct Settlement: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let groupID: UUID
    let fromUserID: UUID     // payer
    let toUserID: UUID       // recipient
    let amount: Decimal
    let currency: String
    let recordedBy: UUID
    let createdAt: Date

    /// Retained here because `PaymentLinkService` and `ProfileView` refer to
    /// `Settlement.PaymentMethod`. Not a property of a ledger row.
    enum PaymentMethod: String, Codable, Sendable {
        case cash         = "cash"
        case upi          = "upi"
        case paypal       = "paypal"
        case venmo        = "venmo"
        case bankTransfer = "bank_transfer"
        case other        = "other"
    }

    enum CodingKeys: String, CodingKey {
        case id, amount, currency
        case groupID    = "group_id"
        case fromUserID = "from_user_id"
        case toUserID   = "to_user_id"
        case recordedBy = "recorded_by"
        case createdAt  = "created_at"
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

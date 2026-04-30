//
//  IOU.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

struct IOU: Codable, Identifiable, Sendable {
    let id: UUID
    let createdBy: UUID
    let lenderID: UUID    // person who is owed (creditor)
    let borrowerID: UUID  // person who owes (debtor)
    var amount: Decimal
    var currency: String
    var description: String?
    var isSettled: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case createdBy   = "created_by"
        case lenderID    = "lender_id"
        case borrowerID  = "borrower_id"
        case amount
        case currency
        case description
        case isSettled   = "is_settled"
        case createdAt   = "created_at"
    }
}

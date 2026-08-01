//
//  Split.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import OSLog

// MARK: - Split

struct Split: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let expenseID: UUID
    let userID: UUID
    var amount: Decimal
    var percentage: Decimal?
    /// **Legacy. Read by nothing, written by nothing.** `public.settlements` (migration 041)
    /// replaced this as the record of who has paid whom; balances are now every split minus
    /// every settlement. The column and these two properties are retained for one release so
    /// the pre-migration state can be re-derived if the backfill proves wrong.
    ///
    /// Do not add a write path back. The one that existed — `ExpenseService.settleSplit` —
    /// was deleted precisely because a method named "settle" that returns HTTP 200 and moves
    /// no balance is worse than no method at all. Record a payment through
    /// `SettlementService.recordSettlement` instead.
    var isSettled: Bool
    var settledAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case expenseID  = "expense_id"
        case userID     = "user_id"
        case amount
        case percentage
        case isSettled  = "is_settled"
        case settledAt  = "settled_at"
    }
}

// MARK: - SplitStrategy

enum SplitStrategy: String, CaseIterable, Sendable {
    case equal      = "equal"
    case percentage = "percentage"
    case exact      = "exact"
    case shares     = "shares"

    var displayName: String {
        switch self {
        case .equal:      return "Equal"
        case .percentage: return "By %"
        case .exact:      return "Exact"
        case .shares:     return "Shares"
        }
    }
}

// MARK: - SplitInput (used when creating/editing an expense)

struct SplitInput: Identifiable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    var displayName: String
    var avatarURL: URL?
    var amount: Decimal
    var percentage: Decimal
    var shares: Int
    var isIncluded: Bool

    init(userID: UUID, displayName: String, avatarURL: URL? = nil) {
        self.id          = UUID()
        self.userID      = userID
        self.displayName = displayName
        self.avatarURL   = avatarURL
        self.amount      = .zero
        self.percentage  = .zero
        self.shares      = 1
        self.isIncluded  = true
    }

    /// Convenience init for replicating a saved split (e.g. recurring expense instances).
    /// NOTE: `displayName` is left empty; callers must set it after init for correct display.
    init(from split: Split) {
        self.id          = UUID()
        self.userID      = split.userID
        self.displayName = ""
        self.avatarURL   = nil
        self.amount      = split.amount
        self.percentage  = split.percentage ?? .zero
        self.shares      = 1
        self.isIncluded  = true
        // displayName is intentionally left empty — callers must populate it after construction.
        Logger(subsystem: "com.vijaygoyal.xbill", category: "SplitInput")
            .fault("SplitInput(from:) called without displayName — caller must populate it after init")
    }
}

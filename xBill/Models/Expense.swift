//
//  Expense.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

// MARK: - Expense

struct Expense: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let groupID: UUID
    var title: String
    var amount: Decimal
    var currency: String
    var payerID: UUID?
    var category: Category
    var notes: String?
    var receiptURL: URL?
    var originalAmount: Decimal?
    var originalCurrency: String?
    var recurrence: Recurrence
    var nextOccurrenceDate: Date?
    let createdAt: Date

    // MARK: - Category

    enum Category: String, Codable, CaseIterable, Sendable {
        case food          = "food"
        case transport     = "transport"
        case accommodation = "accommodation"
        case entertainment = "entertainment"
        case utilities     = "utilities"
        case shopping      = "shopping"
        case health        = "health"
        case other         = "other"

        // L-01: Graceful fallback for unknown future DB values.
        // Without this, a new category added in a future migration would cause
        // the entire Expense to fail to decode rather than gracefully falling back.
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            self = Self(rawValue: raw) ?? .other
        }

        var displayName: String {
            switch self {
            case .food:          return "Food & Drink"
            case .transport:     return "Transport"
            case .accommodation: return "Accommodation"
            case .entertainment: return "Entertainment"
            case .utilities:     return "Utilities"
            case .shopping:      return "Shopping"
            case .health:        return "Health"
            case .other:         return "Other"
            }
        }

        var systemImage: String {
            switch self {
            case .food:          return "fork.knife"
            case .transport:     return "car.fill"
            case .accommodation: return "house.fill"
            case .entertainment: return "film.fill"
            case .utilities:     return "bolt.fill"
            case .shopping:      return "bag.fill"
            case .health:        return "heart.fill"
            case .other:         return "ellipsis.circle.fill"
            }
        }
    }

    // MARK: - Recurrence

    enum Recurrence: String, Codable, CaseIterable, Equatable, Sendable {
        case none    = "none"
        case weekly  = "weekly"
        case monthly = "monthly"
        case yearly  = "yearly"

        // L-01: Graceful fallback for unknown future DB values.
        // Without this, a new recurrence cadence added in a future migration would cause
        // the entire Expense to fail to decode rather than gracefully falling back.
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            self = Self(rawValue: raw) ?? .none
        }

        var displayName: String {
            switch self {
            case .none:    return "Does not repeat"
            case .weekly:  return "Weekly"
            case .monthly: return "Monthly"
            case .yearly:  return "Yearly"
            }
        }

        var shortLabel: String {
            switch self {
            case .none:    return ""
            case .weekly:  return "Weekly"
            case .monthly: return "Monthly"
            case .yearly:  return "Yearly"
            }
        }

        func nextDate(from date: Date) -> Date? {
            let cal = Calendar.current
            switch self {
            case .none:    return nil  // Non-recurring; no next date exists.
            case .weekly:  return cal.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
            case .monthly: return cal.date(byAdding: .month,      value: 1, to: date) ?? date
            case .yearly:  return cal.date(byAdding: .year,       value: 1, to: date) ?? date
            }
        }
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case groupID    = "group_id"
        case title
        case amount
        case currency
        case payerID    = "paid_by"
        case category
        case notes
        case receiptURL           = "receipt_url"
        case originalAmount       = "original_amount"
        case originalCurrency     = "original_currency"
        case recurrence
        case nextOccurrenceDate   = "next_occurrence_date"
        case createdAt            = "created_at"
    }
}

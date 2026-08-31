//
//  AppError.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Supabase

// MARK: - ErrorAlert

struct ErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - AppError

enum AppError: LocalizedError, Equatable {
    case networkUnavailable
    case unauthenticated
    case confirmationRequired   // sign-up succeeded but email confirmation is pending
    case notFound
    case permissionDenied
    case decodingFailed(String)
    case serverError(String)
    case validationFailed(String)
    case editConflict
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "No internet connection. Please check your network and try again."
        case .unauthenticated:
            return "Please sign in to continue."
        case .confirmationRequired:
            return "Check your email to confirm your account, then sign in."
        case .notFound:
            return "The requested resource was not found."
        case .permissionDenied:
            return "You don't have permission to perform this action."
        case .decodingFailed(let detail):
            return "Data error: \(detail)"
        case .serverError(let message):
            return message
        case .validationFailed(let message):
            return message
        case .editConflict:
            return "This expense was changed by someone else"
        case .unknown(let message):
            return message
        }
    }

    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError { return appError }
        // M-30: map CancellationError to a sentinel message so isSilent can suppress it.
        // Navigation-triggered task cancellations should never surface as error alerts.
        if error is CancellationError { return .unknown("cancelled") }
        return .unknown(error.localizedDescription)
    }

    /// SQLSTATE raised by `update_expense_with_splits` when the row moved under the editor.
    ///
    /// Matched on the structured `code`, never on message text — see `EditConflictMappingTests`.
    static let editConflictCode = "XB409"

    static func isEditConflict(_ error: Error) -> Bool {
        guard let pg = error as? PostgrestError else { return false }
        return pg.code == editConflictCode
    }

    /// Returns true if this error should be silently ignored and never shown to the user.
    static func isSilent(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        // M-30: also silence the sentinel produced by from(_:) for CancellationError.
        if case .unknown(let msg) = AppError.from(error), msg == "cancelled" { return true }
        return false
    }
}

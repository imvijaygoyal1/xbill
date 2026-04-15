import Foundation

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
        case .unknown(let message):
            return message
        }
    }

    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError { return appError }
        return .unknown(error.localizedDescription)
    }
}

import Foundation
import Observation

struct InviteJoinRequest: Identifiable, Sendable {
    let id = UUID()
    let token: String
}

@Observable
@MainActor
final class AuthViewModel {

    // MARK: - State

    var email: String = ""
    var password: String = ""
    var displayName: String = ""
    var confirmPassword: String = ""

    var isSigningUp: Bool = false
    var isLoading: Bool = false
    var error: AppError?
    var currentUser: User?
    var confirmationEmailSent: Bool = false
    var isInPasswordRecovery: Bool = false
    var pendingJoinRequest: InviteJoinRequest?

    var isLoggedIn: Bool { currentUser != nil }

    private let auth = AuthService.shared

    // MARK: - Computed

    var isEmailValid: Bool {
        email.contains("@") && email.contains(".")
    }

    var isPasswordValid: Bool { password.count >= 8 }

    var passwordsMatch: Bool { password == confirmPassword }

    var canSubmit: Bool {
        isEmailValid && isPasswordValid &&
        (isSigningUp ? passwordsMatch && !displayName.isEmpty : true)
    }

    // MARK: - Auth State Listener

    /// Subscribes to Supabase auth state changes for the lifetime of the caller's Task.
    /// Call this from the app root so sign-in / sign-out propagates everywhere.
    func startListeningToAuthChanges() async {
        for await (event, session) in SupabaseManager.shared.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                // Don't navigate into the app until the email is confirmed.
                // emailConfirmedAt is nil for unconfirmed sign-ups even when a
                // temporary session is issued by Supabase.
                guard session?.user.emailConfirmedAt != nil else { break }
                if currentUser == nil {
                    await loadCurrentUser()
                }
            case .passwordRecovery:
                isInPasswordRecovery = true
            case .signedOut:
                currentUser = nil
                isInPasswordRecovery = false
            default:
                break
            }
        }
    }

    // MARK: - Actions

    func signIn() async {
        guard canSubmit else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            currentUser = try await auth.signInWithEmail(email: email, password: password)
            error = nil  // clear only on success
        } catch {
            self.error = AppError.from(error)
        }
    }

    func signUp() async {
        guard canSubmit else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            currentUser = try await auth.signUpWithEmail(
                email: email,
                password: password,
                displayName: displayName
            )
            error = nil  // clear only on success
        } catch AppError.confirmationRequired {
            error = nil
            confirmationEmailSent = true
        } catch {
            self.error = AppError.from(error)
        }
    }

    func signInWithApple(idToken: String, nonce: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            currentUser = try await auth.signInWithApple(idToken: idToken, nonce: nonce)
        } catch {
            self.error = AppError.from(error)
        }
    }

    func handlePasswordReset(newPassword: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await SupabaseManager.shared.auth.update(user: .init(password: newPassword))
            isInPasswordRecovery = false
            await loadCurrentUser()
        } catch {
            self.error = AppError.from(error)
        }
    }

    func sendPasswordReset() async {
        guard isEmailValid else {
            error = .validationFailed("Please enter a valid email address.")
            return
        }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await auth.sendPasswordReset(email: email)
        } catch {
            self.error = AppError.from(error)
        }
    }

    func signOut() async {
        do {
            try await auth.signOut()
            // currentUser is cleared by the auth-state listener (.signedOut event)
        } catch {
            self.error = AppError.from(error)
        }
    }

    func loadCurrentUser() async {
        do {
            currentUser = try await auth.currentUser()
        } catch {
            currentUser = nil
        }
    }

    func toggleMode() {
        isSigningUp.toggle()
        error = nil
        password = ""
        confirmPassword = ""
    }
}

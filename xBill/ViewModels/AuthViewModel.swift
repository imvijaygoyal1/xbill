//
//  AuthViewModel.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

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
    var errorAlert: ErrorAlert?
    var currentUser: User?
    var confirmationEmailSent: Bool = false
    var isInPasswordRecovery: Bool = false
    var pendingJoinRequest: InviteJoinRequest?

    var isLoggedIn: Bool { currentUser != nil }

    private let auth = AuthService.shared
    @ObservationIgnored private var isListening = false

    // MARK: - Computed

    var isEmailValid: Bool {
        // RFC 5322 simplified: require at least one character before @,
        // a domain label, a dot, and at least 2 characters for TLD.
        let regex = #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#
        return email.range(of: regex, options: .regularExpression) != nil
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
    /// Guards against duplicate subscriptions if called more than once.
    func startListeningToAuthChanges() async {
        guard !isListening else { return }
        isListening = true
        defer { isListening = false }

        for await (event, session) in SupabaseManager.shared.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                // .initialSession fires on every cold launch, with session == nil when no user
                // is signed in. Calling loadCurrentUser() in that case makes a network round-trip
                // that always throws, which previously cleared currentUser and contributed to the
                // landing-page ↔ welcome-screen loop. Skip if there is no session.
                guard session != nil else { break }
                // Block unconfirmed email/password sign-ups only.
                // OAuth providers (Apple, etc.) are pre-verified — emailConfirmedAt is nil for them
                // but they must still be allowed through.
                let isEmailProvider = session?.user.appMetadata["provider"] == "email"
                guard session?.user.emailConfirmedAt != nil || !isEmailProvider else { break }
                // Always refresh on userUpdated (profile/password changes) so currentUser stays current.
                await loadCurrentUser()
            case .passwordRecovery:
                isInPasswordRecovery = true
            case .signedOut:
                currentUser = nil
                isInPasswordRecovery = false
                AppState.shared.clear()
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
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Sign In Failed", message: error.localizedDescription)
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
        } catch AppError.confirmationRequired {
            confirmationEmailSent = true
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Sign Up Failed", message: error.localizedDescription)
        }
    }

    func signInWithApple(idToken: String, nonce: String, displayName: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            currentUser = try await auth.signInWithApple(idToken: idToken, nonce: nonce, displayName: displayName)
        } catch {
            guard !AppError.isSilent(error) else { return }
            self.errorAlert = ErrorAlert(title: "Sign In Failed", message: error.localizedDescription)
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
            self.errorAlert = ErrorAlert(title: "Reset Failed", message: error.localizedDescription)
        }
    }

    func sendPasswordReset() async {
        guard isEmailValid else {
            errorAlert = ErrorAlert(title: "Invalid Email", message: "Please enter a valid email address.")
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await auth.sendPasswordReset(email: email)
        } catch {
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }

    func signOut() async {
        do {
            try await auth.signOut()
            // currentUser is cleared by the auth-state listener (.signedOut event)
        } catch {
            self.errorAlert = ErrorAlert(title: "Sign Out Failed", message: error.localizedDescription)
        }
    }

    func loadCurrentUser() async {
        do {
            currentUser = try await auth.currentUser()
        } catch {
            // Do NOT clear currentUser here. Transient network errors, timeouts, and
            // decode failures should not sign the user out of the UI. The .signedOut
            // auth event is the sole authoritative signal for clearing currentUser.
            // Clearing on any error was the second cause of the landing-page loop:
            // a race between two concurrent loadCurrentUser() calls meant whichever
            // threw first wiped out the result of the one that succeeded.
        }
    }

    func toggleMode() {
        isSigningUp.toggle()
        // Only clear a stale error when no concurrent operation is in flight;
        // clearing while isLoading could race with an error assignment mid-flight.
        if !isLoading { errorAlert = nil }
        password = ""
        confirmPassword = ""
    }
}

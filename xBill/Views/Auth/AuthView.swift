//
//  AuthView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI
import AuthenticationServices
import CryptoKit

struct AuthView: View {
    @Bindable var vm: AuthViewModel
    @State private var currentNonce: String?
    @State private var showPrivacy = false
    @State private var showTerms   = false
    @State private var showEmailAuth = false

    var body: some View {
        NavigationStack {
            XBillScreenContainer(
                horizontalPadding: AppSpacing.lg,
                bottomPadding: AppSpacing.xxl
            ) {
                brandHeader

                XBillSplitBillIllustration(size: 220)
                    .frame(maxWidth: .infinity)

                // MARK: Confirmation Banner
                if vm.confirmationEmailSent {
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: "envelope.badge.fill")
                            .foregroundStyle(AppColors.primary)
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("Check your email")
                                .font(.appTitle)
                                .foregroundStyle(AppColors.textPrimary)
                            Text("Tap the link we sent to \(vm.email) to confirm your account, then sign in.")
                                .font(.appCaption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    .xbillCard()
                }

                authCard

                legalLinks
            }
            .navigationDestination(isPresented: $showEmailAuth) {
                EmailAuthView(vm: vm)
            }
        }
        .overlay {
            if vm.isLoading {
                LoadingOverlay(message: "Signing in…")
            }
        }
        .errorAlert(item: $vm.errorAlert)
    }

    // MARK: - Content

    private var brandHeader: some View {
        VStack(spacing: AppSpacing.sm) {
            XBillLogoMark(size: 72)
            Text("xBill")
                .font(.appDisplay)
                .foregroundStyle(AppColors.textPrimary)
            Text("Split expenses, not friendships.")
                .font(.appBody)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.lg)
    }

    private var authCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Welcome back")
                    .font(.appH2)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Sign in to split expenses with your groups and friends.")
                    .font(.appBody)
                    .foregroundStyle(AppColors.textSecondary)
            }

            SignInWithAppleButton(.signIn) { request in
                let nonce = Self.randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = Self.sha256(nonce)
            } onCompletion: { result in
                handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: AppSpacing.controlHeight)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))

            XBillPrimaryButton(title: "Continue with Email", icon: "envelope.fill") {
                HapticManager.selection()
                showEmailAuth = true
            }
        }
        .xbillCard()
    }

    private var legalLinks: some View {
        VStack(spacing: AppSpacing.xs) {
            Text("By continuing, you agree to xBill's")
                .font(.appCaption)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: AppSpacing.sm) {
                Button {
                    showTerms = true
                    HapticManager.selection()
                } label: {
                    Text("Terms of Service")
                        .font(.appCaption)
                        .foregroundStyle(AppColors.primary)
                        .underline()
                        .frame(minHeight: AppSpacing.tapTarget)
                }
                .buttonStyle(.plain)

                Text("and")
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textSecondary)

                Button {
                    showPrivacy = true
                    HapticManager.selection()
                } label: {
                    Text("Privacy Policy")
                        .font(.appCaption)
                        .foregroundStyle(AppColors.primary)
                        .underline()
                        .frame(minHeight: AppSpacing.tapTarget)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showTerms) {
            TermsOfServiceView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .safariSheet(isPresented: $showPrivacy, url: XBillURLs.privacyPolicy)
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let nonce = currentNonce,
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8)
            else {
                vm.errorAlert = ErrorAlert(title: "Sign In Failed", message: "Apple Sign In credential invalid.")
                return
            }
            let nameParts = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            Task { await vm.signInWithApple(idToken: token, nonce: nonce, displayName: nameParts.isEmpty ? nil : nameParts) }
        case .failure(let error):
            let nsError = error as NSError
            if nsError.code != ASAuthorizationError.canceled.rawValue {
                vm.errorAlert = ErrorAlert(title: "Sign In Failed", message: error.localizedDescription)
            }
        }
    }

    // MARK: - Nonce Helpers

    private static func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &randomBytes)
        precondition(status == errSecSuccess, "Failed to generate nonce: \(status)")
        return randomBytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    AuthView(vm: AuthViewModel())
}

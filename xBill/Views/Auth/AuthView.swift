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

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgSecondary.ignoresSafeArea()

                VStack(spacing: XBillSpacing.xxl) {
                    // MARK: Wordmark — Ube swatch hero section
                    VStack(spacing: XBillSpacing.sm) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.white)
                            .accessibilityHidden(true)
                        Text("xBill")
                            .font(.xbillLargeTitle)
                            .foregroundStyle(.white)
                        Text("Split expenses, not friendships.")
                            .font(.xbillBodyMedium)
                            .foregroundStyle(Color.clayUbeLight)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, XBillSpacing.xxxl)
                    .swatchSection(Color.clayUbe, radius: XBillRadius.card)
                    .padding(.horizontal, XBillSpacing.base)
                    .padding(.top, 60)

                    // MARK: Confirmation Banner
                    if vm.confirmationEmailSent {
                        HStack(spacing: XBillSpacing.md) {
                            Image(systemName: "envelope.badge.fill")
                                .foregroundStyle(Color.brandPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Check your email")
                                    .font(.xbillLabel)
                                    .foregroundStyle(Color.textPrimary)
                                Text("Tap the link we sent to **\(vm.email)** to confirm your account, then sign in.")
                                    .font(.xbillCaption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .padding(XBillSpacing.base)
                        .background(Color.brandSurface)
                        .clipShape(RoundedRectangle(cornerRadius: XBillRadius.md))
                        .padding(.horizontal, XBillSpacing.xl)
                    }

                    Spacer()

                    // MARK: Auth Buttons
                    VStack(spacing: XBillSpacing.md) {
                        SignInWithAppleButton(.signIn) { request in
                            let nonce = Self.randomNonceString()
                            currentNonce = nonce
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = Self.sha256(nonce)
                        } onCompletion: { result in
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
                                Task { await vm.signInWithApple(idToken: token, nonce: nonce) }
                            case .failure(let error):
                                let nsError = error as NSError
                                if nsError.code != ASAuthorizationError.canceled.rawValue {
                                    vm.errorAlert = ErrorAlert(title: "Sign In Failed", message: error.localizedDescription)
                                }
                            }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: XBillRadius.md))

                        NavigationLink {
                            EmailAuthView(vm: vm)
                        } label: {
                            Label("Continue with Email", systemImage: "envelope.fill")
                                .font(.xbillButtonLarge)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.brandPrimary)
                                .foregroundStyle(Color.textInverse)
                                .clipShape(RoundedRectangle(cornerRadius: XBillRadius.md))
                        }
                    }
                    .padding(.horizontal, XBillSpacing.xl)

                    HStack(spacing: 4) {
                        Text("By continuing, you agree to our")
                            .font(.xbillCaption)
                            .foregroundStyle(Color.textTertiary)

                        Button {
                            showTerms = true
                            HapticManager.selection()
                        } label: {
                            Text("Terms of Service")
                                .font(.xbillCaption)
                                .foregroundStyle(Color.brandPrimary)
                                .underline()
                        }
                        .buttonStyle(.plain)

                        Text("and")
                            .font(.xbillCaption)
                            .foregroundStyle(Color.textTertiary)

                        Button {
                            showPrivacy = true
                            HapticManager.selection()
                        } label: {
                            Text("Privacy Policy")
                                .font(.xbillCaption)
                                .foregroundStyle(Color.brandPrimary)
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, XBillSpacing.xxxl)
                    .sheet(isPresented: $showTerms) {
                        TermsOfServiceView()
                            .presentationDetents([.large])
                            .presentationDragIndicator(.visible)
                    }
                    .safariSheet(isPresented: $showPrivacy, url: XBillURLs.privacyPolicy)
                }
            }
        }
        .overlay {
            if vm.isLoading {
                LoadingOverlay(message: "Signing in…")
            }
        }
        .errorAlert(item: $vm.errorAlert)
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

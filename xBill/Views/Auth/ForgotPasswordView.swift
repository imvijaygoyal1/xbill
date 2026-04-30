//
//  ForgotPasswordView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var isLoading = false
    @State private var emailSent = false
    @State private var errorMessage: String?

    // Accept the pre-filled email from EmailAuthView if user already typed it
    var prefillEmail: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Icon + heading ──────────────────────────────────
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: XBillRadius.lg)
                            .fill(Color.brandSurface)
                            .frame(width: 64, height: 64)
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.brandPrimary)
                    }

                    Text("Reset your password")
                        .font(.xbillLargeTitle)
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Enter the email address on your xBill account and we'll send you a reset link.")
                        .font(.xbillBodyMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(.top, 32)
                .padding(.horizontal, XBillSpacing.xl)

                Spacer().frame(height: 32)

                // ── Form or success state ───────────────────────────
                if emailSent {
                    successView
                } else {
                    formView
                }

                Spacer()
            }
            .background(Color.bgSecondary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                        .font(.xbillBodyMedium)
                }
            }
        }
    }

    // ── Form view ────────────────────────────────────────────────────
    private var formView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                XBillTextField(
                    placeholder: "your@email.com",
                    text: $email,
                    keyboardType: .emailAddress
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onAppear { email = prefillEmail }

                // Inline error message — stays visible until user edits
                if let error = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13))
                        Text(error)
                            .font(.xbillCaption)
                    }
                    .foregroundStyle(Color.moneyNegative)
                    .padding(.horizontal, 4)
                    .onChange(of: email) {
                        // Clear error as soon as user starts editing
                        errorMessage = nil
                    }
                }
            }
            .padding(.horizontal, XBillSpacing.xl)

            // Send button
            XBillButton(
                title: "Send reset link",
                style: .primary,
                isLoading: isLoading
            ) {
                Task { await sendReset() }
            }
            .padding(.horizontal, XBillSpacing.xl)
            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(email.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
    }

    // ── Success view ─────────────────────────────────────────────────
    private var successView: some View {
        VStack(spacing: 20) {
            // Success card
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.moneyPositive)

                Text("Check your inbox")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                VStack(spacing: 6) {
                    Text("We sent a reset link to")
                        .font(.xbillBodySmall)
                        .foregroundStyle(Color.textSecondary)
                    Text(email)
                        .font(.xbillBodySmall)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.brandPrimary)
                }

                Divider()
                    .padding(.vertical, 4)

                // Helpful tips
                VStack(alignment: .leading, spacing: 8) {
                    HintRow(
                        icon: "clock",
                        text: "The link expires in 1 hour"
                    )
                    HintRow(
                        icon: "envelope.open",
                        text: "Check your spam folder if you don't see it"
                    )
                    HintRow(
                        icon: "at",
                        text: "Make sure you used the email linked to your xBill account"
                    )
                }
            }
            .padding(XBillSpacing.xl)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XBillRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: XBillRadius.lg)
                    .stroke(Color.separator, lineWidth: 0.5)
            )
            .padding(.horizontal, XBillSpacing.xl)

            // Resend option with cooldown
            ResendButtonView(email: email)

            // Close button
            XBillButton(title: "Done", style: .primary) {
                dismiss()
            }
            .padding(.horizontal, XBillSpacing.xl)
        }
    }

    // ── Action ───────────────────────────────────────────────────────
    private func sendReset() async {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await AuthService.shared.sendPasswordReset(email: trimmed)
            await MainActor.run {
                isLoading = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    emailSent = true
                }
                HapticManager.success()
            }
        } catch {
            await MainActor.run {
                isLoading = false
                let desc = error.localizedDescription.lowercased()
                if desc.contains("rate limit") {
                    errorMessage = "Too many attempts. Please wait a few minutes and try again."
                } else if desc.contains("invalid") {
                    errorMessage = "That doesn't look like a valid email address."
                } else if desc.contains("not found") || desc.contains("user") {
                    // Don't reveal whether email exists — security best practice
                    // Show success anyway so attackers can't enumerate accounts
                    withAnimation { emailSent = true }
                } else {
                    errorMessage = "Couldn't send the reset email. Check your connection and try again."
                }
                HapticManager.error()
            }
        }
    }
}

// ── HintRow ──────────────────────────────────────────────────────────

private struct HintRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.brandAccent)
                .frame(width: 16)
            Text(text)
                .font(.xbillCaption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// ── ResendButtonView ──────────────────────────────────────────────────

private struct ResendButtonView: View {
    let email: String
    @State private var cooldown = 30
    @State private var isResending = false
    @State private var cooldownTask: Task<Void, Never>?

    var body: some View {
        Group {
            if cooldown > 0 {
                Text("Resend in \(cooldown)s")
                    .font(.xbillCaption)
                    .foregroundStyle(Color.textTertiary)
            } else {
                Button {
                    Task { await resend() }
                } label: {
                    Text(isResending ? "Sending…" : "Resend email")
                        .font(.xbillCaption)
                        .foregroundStyle(Color.brandPrimary)
                        .underline()
                }
                .disabled(isResending)
            }
        }
        .onAppear { startCooldown() }
        .onDisappear { cooldownTask?.cancel() }
    }

    @MainActor
    private func startCooldown() {
        cooldownTask?.cancel()
        cooldown = 30
        cooldownTask = Task { @MainActor in
            for remaining in stride(from: 29, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                cooldown = remaining
            }
        }
    }

    private func resend() async {
        isResending = true
        try? await AuthService.shared.sendPasswordReset(email: email)
        await MainActor.run {
            isResending = false
            HapticManager.success()
            startCooldown()
        }
    }
}

#Preview {
    ForgotPasswordView(prefillEmail: "user@example.com")
}

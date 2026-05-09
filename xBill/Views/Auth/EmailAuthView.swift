//
//  EmailAuthView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct EmailAuthView: View {
    @Bindable var vm: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var showForgotPassword = false

    private enum Field: Hashable { case email, password, confirm, name }

    // True whenever the keyboard is up — drives illustration hide and scroll layout.
    private var keyboardVisible: Bool { focusedField != nil }

    var body: some View {
        XBillScreenBackground {
            // Plain ScrollView + VStack instead of XBillScreenContainer → XBillScrollView
            // → LazyVStack. LazyVStack triggers layout recalculation mid-scroll when the
            // keyboard resizes the viewport, contributing to the jump. VStack is eager and
            // stable for small, static form content.
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    XBillPageHeader(
                        title: vm.isSigningUp ? "Create Account" : "Sign In",
                        subtitle: vm.isSigningUp
                            ? "Use your name, email, and a secure password."
                            : "Enter your xBill email and password.",
                        showsBackButton: true,
                        backAction: { dismiss() }
                    )
                    .padding(.horizontal, -AppSpacing.lg)

                    // Illustration collapses when the keyboard is up. Without this the
                    // ScrollView must jump 190pt to bring the form card into view —
                    // the largest single contributor to the perceived jumpiness.
                    if !keyboardVisible {
                        XBillWalletIllustration(size: 190)
                            .frame(maxWidth: .infinity)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    formCard
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xxl)
                // Animate the illustration appearing/disappearing and the resulting
                // VStack height change in one coordinated pass.
                .animation(.easeInOut(duration: 0.2), value: keyboardVisible)
            }
            // Let the user drag the scroll view to dismiss the keyboard naturally.
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarBackButtonHidden()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(AppColors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .errorAlert(item: $vm.errorAlert)
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(prefillEmail: vm.email)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Form card

    private var formCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if vm.isSigningUp {
                XBillTextField(
                    placeholder: "Your name",
                    text: $vm.displayName,
                    isFocused: focusedField == .name
                )
                .focused($focusedField, equals: .name)
            }

            XBillTextField(
                placeholder: "you@example.com",
                text: $vm.email,
                keyboardType: .emailAddress,
                isFocused: focusedField == .email
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($focusedField, equals: .email)
            .submitLabel(.next)
            .onSubmit { focusedField = .password }

            XBillTextField(
                placeholder: "Min. 8 characters",
                text: $vm.password,
                isSecure: true,
                isFocused: focusedField == .password
            )
            .focused($focusedField, equals: .password)
            .submitLabel(.go)
            .onSubmit {
                focusedField = nil
                Task {
                    if vm.isSigningUp { await vm.signUp() }
                    else              { await vm.signIn() }
                }
            }

            if vm.isSigningUp {
                XBillTextField(
                    placeholder: "Repeat password",
                    text: $vm.confirmPassword,
                    isSecure: true,
                    isFocused: focusedField == .confirm
                )
                .focused($focusedField, equals: .confirm)

                if !vm.confirmPassword.isEmpty && !vm.passwordsMatch {
                    Text("Passwords don't match.")
                        .font(.appCaption)
                        .foregroundStyle(AppColors.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            XBillPrimaryButton(
                title: vm.isSigningUp ? "Create Account" : "Sign In",
                icon: vm.isSigningUp ? "person.badge.plus" : "arrow.right",
                isLoading: vm.isLoading,
                isDisabled: !vm.canSubmit
            ) {
                focusedField = nil
                Task {
                    if vm.isSigningUp { await vm.signUp() }
                    else              { await vm.signIn() }
                }
            }

            Button { vm.toggleMode() } label: {
                Text(vm.isSigningUp
                     ? "Already have an account? **Sign In**"
                     : "No account? **Create one**")
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppSpacing.tapTarget)
            }
            .buttonStyle(.plain)

            if !vm.isSigningUp {
                Button {
                    showForgotPassword = true
                    HapticManager.selection()
                } label: {
                    Text("Forgot password?")
                        .font(.appCaption)
                        .foregroundStyle(AppColors.primary)
                        .underline()
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppSpacing.tapTarget)
                }
                .buttonStyle(.plain)
            }
        }
        .xbillCard()
    }
}

#Preview {
    NavigationStack {
        EmailAuthView(vm: AuthViewModel())
    }
}

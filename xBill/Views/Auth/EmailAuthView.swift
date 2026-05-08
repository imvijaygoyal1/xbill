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

    var body: some View {
        XBillScreenContainer(
            horizontalPadding: AppSpacing.lg,
            bottomPadding: AppSpacing.xxl
        ) {
            XBillPageHeader(
                title: vm.isSigningUp ? "Create Account" : "Sign In",
                subtitle: vm.isSigningUp ? "Use your name, email, and a secure password." : "Enter your xBill email and password.",
                showsBackButton: true,
                backAction: { dismiss() }
            )
            .padding(.horizontal, -AppSpacing.lg)

            XBillWalletIllustration(size: 190)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                    // Display Name (sign-up only)
                    if vm.isSigningUp {
                        XBillTextField(placeholder: "Your name", text: $vm.displayName)
                            .focused($focusedField, equals: .name)
                    }

                    // Email
                    XBillTextField(
                        placeholder: "you@example.com",
                        text: $vm.email,
                        keyboardType: .emailAddress
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }

                    // Password
                    XBillTextField(placeholder: "Min. 8 characters", text: $vm.password, isSecure: true)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit {
                            focusedField = nil
                            Task {
                                if vm.isSigningUp { await vm.signUp() }
                                else              { await vm.signIn() }
                            }
                        }

                    // Confirm Password (sign-up only)
                    if vm.isSigningUp {
                        XBillTextField(placeholder: "Repeat password", text: $vm.confirmPassword, isSecure: true)
                            .focused($focusedField, equals: .confirm)

                        if !vm.confirmPassword.isEmpty && !vm.passwordsMatch {
                            Text("Passwords don't match.")
                                .font(.appCaption)
                                .foregroundStyle(AppColors.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // Submit
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

                    // Toggle sign-in / sign-up
                    Button { vm.toggleMode() } label: {
                        Text(vm.isSigningUp ? "Already have an account? **Sign In**" : "No account? **Create one**")
                            .font(.appCaption)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppSpacing.tapTarget)
                    }
                    .buttonStyle(.plain)

                    // Forgot password (sign-in only)
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
}

#Preview {
    NavigationStack {
        EmailAuthView(vm: AuthViewModel())
    }
}

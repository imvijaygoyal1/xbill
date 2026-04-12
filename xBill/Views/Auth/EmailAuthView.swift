import SwiftUI

struct EmailAuthView: View {
    @Bindable var vm: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case email, password, confirm, name }

    var body: some View {
        ZStack {
            Color.bgSecondary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: XBillSpacing.lg) {
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

                    // Password
                    XBillTextField(placeholder: "Min. 8 characters", text: $vm.password, isSecure: true)
                        .focused($focusedField, equals: .password)

                    // Confirm Password (sign-up only)
                    if vm.isSigningUp {
                        XBillTextField(placeholder: "Repeat password", text: $vm.confirmPassword, isSecure: true)
                            .focused($focusedField, equals: .confirm)

                        if !vm.confirmPassword.isEmpty && !vm.passwordsMatch {
                            Text("Passwords don't match.")
                                .font(.xbillCaption)
                                .foregroundStyle(Color.moneyNegative)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // Submit
                    XBillButton(
                        title: vm.isSigningUp ? "Create Account" : "Sign In",
                        style: .primary,
                        isLoading: vm.isLoading
                    ) {
                        focusedField = nil
                        Task {
                            if vm.isSigningUp { await vm.signUp() }
                            else              { await vm.signIn() }
                        }
                    }
                    .disabled(!vm.canSubmit)

                    // Toggle sign-in / sign-up
                    Button { vm.toggleMode() } label: {
                        Text(vm.isSigningUp ? "Already have an account? **Sign In**" : "No account? **Create one**")
                            .font(.xbillBodySmall)
                            .foregroundStyle(Color.textSecondary)
                    }

                    // Forgot password (sign-in only)
                    if !vm.isSigningUp {
                        Button {
                            Task { await vm.sendPasswordReset() }
                        } label: {
                            Text("Forgot password?")
                                .font(.xbillCaption)
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }
                }
                .padding(XBillSpacing.xl)
            }
        }
        .navigationTitle(vm.isSigningUp ? "Create Account" : "Sign In")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.navBarBg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .errorAlert(error: $vm.error)
    }
}

#Preview {
    NavigationStack {
        EmailAuthView(vm: AuthViewModel())
    }
}

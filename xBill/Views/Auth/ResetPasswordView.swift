import SwiftUI

struct ResetPasswordView: View {
    @Bindable var authVM: AuthViewModel

    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isLoading: Bool = false
    @State private var error: AppError?

    private var isValid: Bool {
        newPassword.count >= 8 && newPassword == confirmPassword
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New password", text: $newPassword)
                        .textContentType(.newPassword)
                    SecureField("Confirm password", text: $confirmPassword)
                        .textContentType(.newPassword)
                } header: {
                    Text("Choose a new password")
                } footer: {
                    if !newPassword.isEmpty && newPassword.count < 8 {
                        Text("Password must be at least 8 characters.")
                            .foregroundStyle(.red)
                    } else if !confirmPassword.isEmpty && newPassword != confirmPassword {
                        Text("Passwords do not match.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await submit() }
                        }
                        .disabled(!isValid)
                    }
                }
            }
        }
        .errorAlert(error: $error)
    }

    private func submit() async {
        isLoading = true
        defer { isLoading = false }
        await authVM.handlePasswordReset(newPassword: newPassword)
        if authVM.error != nil {
            error = authVM.error
            authVM.error = nil
        }
    }
}

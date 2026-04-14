import SwiftUI

// MARK: - TermsOfServiceView
// Displayed in-app from AuthView and ProfileView.
// Update the text below with your actual legal terms before App Store submission.

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: XBillSpacing.xl) {

                    Text("Last updated: April 2026")
                        .font(.xbillCaption)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.top, XBillSpacing.base)

                    section(
                        "1. Acceptance of Terms",
                        body: "By creating an account or using xBill, you agree to these Terms of Service. If you do not agree, do not use the app."
                    )
                    section(
                        "2. Description of Service",
                        body: "xBill is an expense-splitting application that lets users create groups, record shared expenses, and track balances with friends and family. xBill does not process real payments — it tracks what people owe each other."
                    )
                    section(
                        "3. Account Responsibility",
                        body: "You are responsible for maintaining the security of your account and for all activity that occurs under it. You must be at least 13 years old to use xBill."
                    )
                    section(
                        "4. User Content",
                        body: "You retain ownership of the expense data, group names, and other content you submit. By using xBill, you grant us a limited licence to store and process that data solely to provide the service."
                    )
                    section(
                        "5. Prohibited Conduct",
                        body: "You agree not to use xBill to harass other users, submit false expense data, attempt to access other users' accounts, or violate any applicable law."
                    )
                    section(
                        "6. Disclaimer of Warranties",
                        body: "xBill is provided \"as is\" without warranties of any kind. We do not guarantee uninterrupted or error-free service."
                    )
                    section(
                        "7. Limitation of Liability",
                        body: "To the fullest extent permitted by law, xBill and its developer shall not be liable for any indirect, incidental, or consequential damages arising from your use of the app."
                    )
                    section(
                        "8. Changes to Terms",
                        body: "We may update these terms at any time. Continued use of xBill after changes constitutes acceptance of the revised terms."
                    )
                    section(
                        "9. Contact",
                        body: "For questions about these terms, contact us at support@xbill.vijaygoyal.org."
                    )

                    Spacer(minLength: XBillSpacing.xxxl)
                }
                .padding(.horizontal, XBillSpacing.xl)
            }
            .background(Color.bgSecondary)
            .navigationTitle("Terms of Service")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
            }
        }
    }

    private func section(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: XBillSpacing.sm) {
            Text(title)
                .font(.xbillLabel)
                .foregroundStyle(Color.textPrimary)
            Text(body)
                .font(.xbillBodySmall)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    TermsOfServiceView()
}

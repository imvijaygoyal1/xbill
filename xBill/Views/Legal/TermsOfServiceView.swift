//
//  TermsOfServiceView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

// MARK: - TermsOfServiceView
// Displayed in-app from AuthView and ProfileView as a native sheet.

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Terms of Service")
                            .font(.xbillLargeTitle)
                            .foregroundStyle(Color.textInverse)
                        Text("Effective: April 12, 2026")
                            .font(.xbillCaption)
                            .foregroundStyle(Color.textInverse.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(XBillSpacing.xl)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: XBillRadius.lg))

                    VStack(alignment: .leading, spacing: 24) {

                        TOSSection(number: "1", title: "Acceptance of terms",
                            content: "By creating an xBill account or using the xBill app, you agree to these Terms of Service. If you do not agree, do not use xBill.")

                        TOSSection(number: "2", title: "What xBill does",
                            content: "xBill helps you track and split shared expenses with friends and groups. It does not process payments — any payments are made directly through third-party services like Venmo.")

                        TOSSection(number: "3", title: "Your account",
                            content: "You must be 13 or older to use xBill. You are responsible for keeping your login credentials secure and for all activity under your account. Notify us immediately at imvijaygoyal1@icloud.com if you suspect unauthorised access.")

                        TOSSection(number: "4", title: "Acceptable use",
                            content: "You agree not to use xBill to harass others, record false expenses, or circumvent security measures. We may suspend or terminate accounts that violate these terms.")

                        TOSSection(number: "5", title: "User content",
                            content: "You own the expense data, group names, and comments you create. By using xBill you grant us a limited licence to store and display that content to provide the service. We do not sell your content.")

                        TOSSection(number: "6", title: "No financial advice",
                            content: "xBill is an expense tracking tool only. Nothing in the app constitutes financial, legal, or accounting advice.")

                        TOSSection(number: "7", title: "Service availability",
                            content: "We aim to keep xBill available at all times but cannot guarantee uninterrupted access. We may update, modify, or discontinue features with reasonable notice.")

                        TOSSection(number: "8", title: "Limitation of liability",
                            content: "To the maximum extent permitted by law, xBill and Vijay Goyal are not liable for any indirect, incidental, or consequential damages arising from your use of the app.")

                        TOSSection(number: "9", title: "Changes to these terms",
                            content: "We may update these terms from time to time. We will notify you via push notification or email for material changes. Continued use after the effective date constitutes acceptance.")

                        TOSSection(number: "10", title: "Contact",
                            content: "Questions? Email us at imvijaygoyal1@icloud.com")

                    }
                    .padding(.bottom, XBillSpacing.xxxl)
                }
                .padding(.horizontal, XBillSpacing.xl)
                .padding(.top, XBillSpacing.base)
            }
            .background(Color.bgSecondary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    XBillWordmark()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                        .font(.xbillBodyMedium)
                }
            }
        }
    }
}

// MARK: - TOSSection

private struct TOSSection: View {
    let number:  String
    let title:   String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.brandSurface)
                        .frame(width: 26, height: 26)
                    Text(number)
                        .font(.xbillCaptionBold)
                        .foregroundStyle(Color.brandPrimary)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
            }
            Text(content)
                .font(.xbillBodySmall)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 36)
        }
        .padding(XBillSpacing.base)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XBillRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XBillRadius.lg)
                .stroke(Color.separator, lineWidth: 0.5)
        )
    }
}

#Preview {
    TermsOfServiceView()
}

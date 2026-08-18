//
//  AboutView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  The app's identity, provenance and credits in one place.
//
//  It exists for three reasons, not one. The obvious one is attribution. The second is that the
//  Profile footer had grown to three stacked lines of tertiary text (legal links, the required
//  ExchangeRate-API credit, the version) and was becoming a dumping ground. The third is the one
//  that actually mattered: xBill ships four third-party packages and had **no acknowledgements
//  surface anywhere**, and the ExchangeRate-API attribution is a licence condition rather than a
//  courtesy — see `XBillURLs.exchangeRateAttribution`.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var showTerms = false
    @State private var showPrivacy = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.xl) {
                        XBillPageHeader(
                            title: "About",
                            showsBackButton: true,
                            backAction: { dismiss() }
                        )

                        identity
                        madeBy
                        supportSection
                        legalSection
                        acknowledgements
                    }
                    .padding(.bottom, AppSpacing.xl)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showTerms) { TermsOfServiceView() }
            .safariSheet(isPresented: $showPrivacy, url: XBillURLs.privacyPolicy)
        }
    }

    // MARK: - Identity

    private var identity: some View {
        VStack(spacing: AppSpacing.sm) {
            XBillLogoMark(size: 72)
            Text("xBill")
                .font(.appH1)
                .foregroundStyle(AppColors.textPrimary)
            Text("Split expenses, not friendships.")
                .font(.appBody)
                .foregroundStyle(AppColors.textSecondary)
            // Build number as well as marketing version: a bug report citing only "1.1" cannot be
            // matched to a specific submission, and the two diverge across resubmissions.
            Text("Version \(version) (\(build))")
                .font(.appCaption)
                .foregroundStyle(AppColors.textTertiary)
                .accessibilityIdentifier("xBill.about.version")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Made by

    private var madeBy: some View {
        XBillFormSection {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("MADE BY")
                    .font(.appCaptionMedium)
                    .foregroundStyle(AppColors.textTertiary)
                Text("Vijay Goyal")
                    .font(.appTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Designed and built in 2026.")
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.md)
        }
        .padding(.horizontal, AppSpacing.lg)
    }

    // MARK: - Support

    private var supportSection: some View {
        XBillFormSection {
            VStack(spacing: 0) {
                // Placed above Contact deliberately: someone opening About is already engaged, and
                // this link is not subject to StoreKit's three-prompts-a-year limit.
                XBillSettingsRow(icon: "star.fill", title: "Rate xBill",
                                 subtitle: "Ratings help other people find the app") {
                    openURL(XBillURLs.appStoreReview)
                }
                .accessibilityIdentifier("xBill.about.rateButton")

                Divider().padding(.leading, AppSpacing.xxl)

                XBillSettingsRow(icon: "envelope.fill", title: "Contact Support") {
                    openURL(XBillURLs.supportMailURL(
                        subject: "xBill \(version) (\(build)) — Support",
                        body: "\n\n—\nVersion \(version) (\(build))"
                    ))
                }
                .accessibilityIdentifier("xBill.about.supportButton")
            }
        }
        .padding(.horizontal, AppSpacing.lg)
    }

    // MARK: - Legal

    private var legalSection: some View {
        XBillFormSection {
            VStack(spacing: 0) {
                XBillSettingsRow(icon: "doc.text.fill", title: "Terms of Service") {
                    showTerms = true
                }
                Divider().padding(.leading, AppSpacing.xxl)
                XBillSettingsRow(icon: "hand.raised.fill", title: "Privacy Policy") {
                    showPrivacy = true
                }
            }
        }
        .padding(.horizontal, AppSpacing.lg)
    }

    // MARK: - Acknowledgements

    /// The ExchangeRate-API row is **required** by that service's Open Access terms — it is not a
    /// courtesy credit and must not be removed while the app calls `open.er-api.com`. The package
    /// rows are MIT/Apache-2.0, which do not compel an in-app notice, but listing them is the
    /// convention and this is the only surface that does it.
    private var acknowledgements: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("ACKNOWLEDGEMENTS")
                .font(.appCaptionMedium)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, AppSpacing.lg)

            XBillFormSection {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Link(destination: XBillURLs.exchangeRateAttribution) {
                        credit("Rates By Exchange Rate API",
                               detail: "Currency conversion rates")
                    }
                    .accessibilityIdentifier("xBill.about.rateAttribution")

                    credit("Supabase Swift", detail: "MIT License")
                    credit("swift-crypto · swift-asn1 · swift-http-types",
                           detail: "Apache License 2.0 — Apple Inc.")
                    credit("swift-clocks · swift-concurrency-extras",
                           detail: "MIT License — Point-Free")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.md)
            }
            .padding(.horizontal, AppSpacing.lg)
        }
    }

    private func credit(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.appTitle)
                .foregroundStyle(AppColors.textPrimary)
            Text(detail)
                .font(.appCaption)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    AboutView()
}

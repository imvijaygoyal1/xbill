//
//  NotificationPermissionView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI
import UIKit

struct NotificationPermissionView: View {
    let onAllow: () async -> Void
    let onSkip:  () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: XBillSpacing.lg) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.brandPrimary)
                    .accessibilityHidden(true)

                VStack(spacing: XBillSpacing.sm) {
                    Text("Stay in the loop")
                        .font(.xbillLargeTitle)
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Get notified when a group member adds an expense or settles up — so you're never caught off guard.")
                        .font(.xbillBodyLarge)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, XBillSpacing.lg)
                }

                VStack(spacing: XBillSpacing.sm) {
                    featureRow(icon: "plus.circle.fill",  color: .brandPrimary,  text: "New expenses from your groups")
                    featureRow(icon: "checkmark.seal.fill", color: .moneyPositive, text: "When someone settles up with you")
                    featureRow(icon: "bubble.left.fill",  color: .brandAccent,   text: "Comments on shared expenses")
                }
                .padding(.horizontal, XBillSpacing.lg)
            }
            .padding(XBillSpacing.xl)
            .asClayCard()
            .padding(.horizontal, XBillSpacing.base)

            Spacer()

            VStack(spacing: XBillSpacing.sm) {
                XBillButton(title: "Allow Notifications", style: .primary) {
                    Task { await onAllow() }
                }

                Button("Not Now") { onSkip() }
                    .font(.xbillBodyMedium)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, XBillSpacing.base)
            .padding(.bottom, XBillSpacing.xl)
        }
        .background(Color.bgSecondary.ignoresSafeArea())
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: XBillSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.body)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.xbillBodyLarge)
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
    }
}

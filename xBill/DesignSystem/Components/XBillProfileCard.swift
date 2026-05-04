//
//  XBillProfileCard.swift
//  xBill
//

import SwiftUI

struct XBillProfileCard: View {
    let user: User?
    let initials: String
    let onEdit: () -> Void
    let onQR: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            AvatarView(name: user?.displayName ?? initials, url: user?.avatarURL, size: XBillIcon.avatarLg)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(user?.displayName ?? "Your profile")
                    .font(.appH2)
                    .foregroundStyle(AppColors.textPrimary)
                if let email = user?.email {
                    Text(email)
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer()
            Button(action: onQR) {
                Image(systemName: "qrcode")
                    .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
            }
            .accessibilityLabel("My QR Code")
            Button("Edit", action: onEdit)
                .font(.appCaptionMedium)
                .frame(minHeight: AppSpacing.tapTarget)
        }
        .xbillCard()
    }
}

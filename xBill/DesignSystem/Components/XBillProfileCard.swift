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
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                if let email = user?.email {
                    Text(email)
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityLabel("Email, \(email)")
                }
            }
            Spacer(minLength: AppSpacing.sm)
            HStack(spacing: AppSpacing.sm) {
                Button(action: onQR) {
                    Image(systemName: "qrcode")
                        .font(.appIcon)
                        .foregroundStyle(AppColors.primary)
                        .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
                        .background(AppColors.surfaceSoft)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("My QR Code")

                Button("Edit", action: onEdit)
                    .font(.appCaptionMedium)
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, AppSpacing.md)
                    .frame(minHeight: AppSpacing.tapTarget)
                    .background(AppColors.surfaceSoft)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit profile")
            }
        }
        .xbillCard(padding: AppSpacing.lg)
    }
}

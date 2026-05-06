//
//  XBillProfileCard.swift
//  xBill
//

import SwiftUI

struct XBillProfileCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let user: User?
    let initials: String
    let onEdit: () -> Void
    let onQR: () -> Void

    var body: some View {
        let shadow = AppShadow.card(colorScheme: colorScheme)

        HStack(alignment: .center, spacing: AppSpacing.md) {
            AvatarView(name: user?.displayName ?? initials, url: user?.avatarURL, size: avatarSize)
                .frame(width: avatarSize, height: avatarSize)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(user?.displayName ?? "Your profile")
                    .font(.appH2)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.9)

                if let email = user?.email {
                    Text(email)
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityLabel("Email, \(email)")
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

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
                .accessibilityLabel("Show QR code")

                Button("Edit", action: onEdit)
                    .font(.appCaptionMedium)
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, AppSpacing.md)
                    .frame(minWidth: AppSpacing.tabBarHeight)
                    .frame(minHeight: AppSpacing.tapTarget)
                    .background(AppColors.surfaceSoft)
                    .clipShape(Capsule())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit profile")
            }
        }
        .padding(AppSpacing.md)
        .frame(minHeight: cardMinHeight)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }

    private var avatarSize: CGFloat {
        AppSpacing.tabBarHeight
    }

    private var cardMinHeight: CGFloat {
        AppSpacing.xxl + AppSpacing.xl + AppSpacing.lg
    }
}

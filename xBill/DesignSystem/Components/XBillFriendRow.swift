//
//  XBillFriendRow.swift
//  xBill
//

import SwiftUI

struct XBillFriendRow<Trailing: View>: View {
    let user: User
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            AvatarView(name: user.displayName, url: user.avatarURL, size: XBillIcon.avatarSm)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(user.displayName)
                    .font(.appTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(user.email)
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            trailing()
        }
        .frame(minHeight: AppSpacing.tapTarget)
    }
}

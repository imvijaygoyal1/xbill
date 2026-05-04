//
//  XBillAvatarStack.swift
//  xBill
//

import SwiftUI

struct XBillAvatarStack: View {
    let users: [User]
    var maxVisible = 4
    var size: CGFloat = 32

    var body: some View {
        HStack(spacing: -AppSpacing.sm) {
            ForEach(Array(users.prefix(maxVisible))) { user in
                AvatarView(name: user.displayName, url: user.avatarURL, size: size)
                    .overlay(Circle().stroke(AppColors.surface, lineWidth: 2))
            }
            if users.isEmpty {
                XBillAvatarPlaceholder(name: "?", size: size)
                    .overlay(Circle().stroke(AppColors.surface, lineWidth: 2))
            }
            if users.count > maxVisible {
                Text("+\(users.count - maxVisible)")
                    .font(.appCaptionMedium)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: size, height: size)
                    .background(AppColors.surfaceSoft)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppColors.surface, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(users.count) members")
    }
}

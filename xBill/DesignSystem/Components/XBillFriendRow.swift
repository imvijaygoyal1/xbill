//
//  XBillFriendRow.swift
//  xBill
//

import SwiftUI

struct XBillFriendRow<Trailing: View>: View {
    let displayName: String
    var detail: String?
    var avatarURL: URL?
    var showsChevron = false
    @ViewBuilder let trailing: () -> Trailing

    init(
        user: User,
        detail: String? = nil,
        showsChevron: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.displayName = user.displayName
        self.detail = detail ?? user.email
        self.avatarURL = user.avatarURL
        self.showsChevron = showsChevron
        self.trailing = trailing
    }

    init(
        displayName: String,
        detail: String? = nil,
        avatarURL: URL? = nil,
        showsChevron: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.displayName = displayName
        self.detail = detail
        self.avatarURL = avatarURL
        self.showsChevron = showsChevron
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            AvatarView(name: displayName, url: avatarURL, size: XBillIcon.avatarSm)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(displayName)
                    .font(.appTitle)
                    .foregroundStyle(AppColors.textPrimary)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            trailing()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.appCaptionMedium)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(minHeight: AppSpacing.tapTarget)
        .contentShape(Rectangle())
    }
}

extension XBillFriendRow where Trailing == EmptyView {
    init(
        user: User,
        detail: String? = nil,
        showsChevron: Bool = false
    ) {
        self.init(user: user, detail: detail, showsChevron: showsChevron) {
            EmptyView()
        }
    }

    init(
        displayName: String,
        detail: String? = nil,
        avatarURL: URL? = nil,
        showsChevron: Bool = false
    ) {
        self.init(displayName: displayName, detail: detail, avatarURL: avatarURL, showsChevron: showsChevron) {
            EmptyView()
        }
    }
}

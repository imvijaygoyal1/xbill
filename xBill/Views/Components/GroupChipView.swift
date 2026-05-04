//
//  GroupChipView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct GroupChipView: View {
    let group: BillGroup

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            XBillAvatarPlaceholder(name: group.emoji, size: AppSpacing.tapTarget)

            Text(group.name)
                .font(.appCaptionMedium)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            Text(group.currency)
                .font(.appCaption)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(width: 116, alignment: .leading)
        .frame(minHeight: 132, alignment: .leading)
        .xbillCard(padding: AppSpacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.name) group, \(group.currency)")
        .accessibilityAddTraits(.isButton)
    }
}

//
//  XBillTabBar.swift
//  xBill
//

import SwiftUI

struct XBillTabBar<Tab: Hashable>: View {
    let tabs: [(Tab, String, String)]
    @Binding var selection: Tab
    var badgeCounts: [Tab: Int] = [:]

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(tabs, id: \.0) { tab, title, icon in
                Button {
                    selection = tab
                    HapticManager.selection()
                } label: {
                    VStack(spacing: AppSpacing.xs) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: icon)
                                .font(.appIcon)
                            if let count = badgeCounts[tab], count > 0 {
                                Text("\(min(count, 99))")
                                    .font(.appBadge)
                                    .foregroundStyle(AppColors.textInverse)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(AppColors.error)
                                    .clipShape(Capsule())
                                    .offset(x: 10, y: -8)
                            }
                        }
                        Text(title)
                            .font(.appTabLabel)
                    }
                    .foregroundStyle(selection == tab ? AppColors.textPrimary : AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppSpacing.tapTarget)
                    .background(selection == tab ? AppColors.surfaceSoft : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.sm)
        .frame(minHeight: AppSpacing.tabBarHeight)
        .background(AppColors.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 1)
        }
    }
}

//
//  ExpenseFilterChip.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Extracted from `GroupDetailView.swift`, which held five top-level types in 1,197 lines and had
//  already been split into `baseContent`/`lifecycleContent`/`decoratedContent` — not for clarity
//  but to escape a Swift type-checker timeout. A file that large is also why logic tends to live
//  in view bodies where no unit test can reach it.
//

import SwiftUI

struct ExpenseFilterChip: View {
    let label: String
    var category: Expense.Category? = nil
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: XBillSpacing.xs) {
                if let category {
                    XBillCategoryIcon(category: category, size: 22)
                }
                Text(label)
                    .font(.xbillLabel)
                    .foregroundStyle(isSelected ? Color.brandPrimary : Color.textSecondary)
            }
            .padding(.horizontal, XBillSpacing.md)
            .padding(.vertical, XBillSpacing.xs)
            .background(isSelected ? Color.brandSurface : Color.bgTertiary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.brandPrimary : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppSpacing.tapTarget)
    }
}

// MARK: - Export helpers

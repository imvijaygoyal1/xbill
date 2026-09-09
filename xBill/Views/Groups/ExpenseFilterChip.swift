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

/// The one category chip. `ExpenseFilterChip` (Group Details filter strip) and the Add Expense
/// category picker were byte-similar copies of this — same HStack, same capsule, same selected
/// stroke — and **neither announced its selected state**, so VoiceOver read "Food & Drink, button"
/// whether the filter was on or off.
///
/// ICON-09. Two copies of one chip is how the edit sheet came to be missing three of four split
/// inputs (SPLIT-05); this project has paid for that shape five times.
struct XBillCategoryChip: View {
    let label: String
    var category: Expense.Category? = nil
    let isSelected: Bool
    var iconSize: CGFloat = 22
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: XBillSpacing.xs) {
                if let category {
                    XBillCategoryIcon(category: category, size: iconSize)
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
        .accessibilityLabel(label)
        // The whole point: without this the selected state is visible only to sighted users.
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Kept as a thin alias so the Group Details filter strip's call sites stay unchanged.
struct ExpenseFilterChip: View {
    let label: String
    var category: Expense.Category? = nil
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        XBillCategoryChip(label: label, category: category, isSelected: isSelected, onTap: onTap)
    }
}

// MARK: - Export helpers

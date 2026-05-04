//
//  XBillExpenseRow.swift
//  xBill
//

import SwiftUI

struct XBillExpenseRow: View {
    let expense: Expense
    let members: [User]
    var showAmountBadge = true

    private var payerName: String {
        members.first(where: { $0.id == expense.payerID })?.displayName ?? "Someone"
    }

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            CategoryIconView(category: expense.category, size: XBillIcon.categorySize)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(expense.title)
                    .font(.appTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text("Paid by \(payerName) · \(expense.createdAt.shortFormatted)")
                    .font(.appCaption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if showAmountBadge {
                AmountBadge(amount: expense.amount, direction: .total, currency: expense.currency)
            } else {
                Text(expense.amount.formatted(currencyCode: expense.currency))
                    .font(.appAmountSm)
                    .foregroundStyle(AppColors.textPrimary)
                    .monospacedDigit()
            }
        }
        .frame(minHeight: AppSpacing.tapTarget)
    }
}

//
//  HomeHeader.swift
//  xBill
//

import SwiftUI

struct HomeHeader: View {
    let user: User?
    let balance: Decimal?
    var date: Date = .now

    private var firstName: String {
        let name = user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.split(separator: " ").first.map(String.init) ?? "there"
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Hi, \(firstName)")
                    .font(.appH2)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(GreetingHelper.greeting(for: date))
                    .font(.appBody)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: AppSpacing.sm)
            if let balance {
                XBillStatusChip(
                    text: BalanceMessageHelper.message(for: balance),
                    icon: balance == .zero ? "checkmark.circle.fill" : balance > .zero ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill",
                    color: balance == .zero ? AppColors.moneySettled : balance > .zero ? AppColors.moneyPositive : AppColors.moneyNegative
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

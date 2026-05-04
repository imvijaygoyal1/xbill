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
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Hi, \(firstName) 👋")
                .font(.appH2)
                .foregroundStyle(AppColors.textPrimary)
            Text(GreetingHelper.greeting(for: date))
                .font(.appCaption)
                .foregroundStyle(AppColors.textSecondary)
            if let balance {
                Text(BalanceMessageHelper.message(for: balance))
                    .font(.appCaption)
                    .foregroundStyle(balance >= .zero ? AppColors.success : AppColors.error)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

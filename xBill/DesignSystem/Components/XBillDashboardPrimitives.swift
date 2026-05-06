//
//  XBillDashboardPrimitives.swift
//  xBill
//

import SwiftUI

struct XBillSectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title.uppercased())
                    .font(.appCaptionMedium)
                    .tracking(1.08)
                    .foregroundStyle(AppColors.textSecondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            Spacer(minLength: AppSpacing.sm)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension XBillSectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}

struct XBillMetricCard: View {
    let title: String
    let amount: Decimal
    let icon: String
    let direction: AmountDirection
    var currency: String = "USD"

    private var color: Color {
        switch direction {
        case .positive:
            AppColors.moneyPositive
        case .negative:
            AppColors.moneyNegative
        case .settled, .total:
            AppColors.moneyTotal
        }
    }

    private var background: Color {
        switch direction {
        case .positive:
            AppColors.moneyPositiveBg
        case .negative:
            AppColors.moneyNegativeBg
        case .settled, .total:
            AppColors.surfaceSoft
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.appCaptionMedium)
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(background)
                    .clipShape(Circle())
                Text(title)
                    .font(.appCaptionMedium)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Text(amount.formatted(currencyCode: currency))
                .font(.appAmountSm)
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 92, alignment: .topLeading)
        .xbillCard(padding: AppSpacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(amount.formatted(currencyCode: currency))")
    }
}

struct XBillStatusChip: View {
    let text: String
    let icon: String
    var color: Color = AppColors.primary

    var body: some View {
        Label(text, systemImage: icon)
            .font(.appCaptionMedium)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct XBillCircularIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.appIcon)
                .foregroundStyle(AppColors.textInverse)
                .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
                .background(AppColors.primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview("Dashboard Primitives") {
    VStack(spacing: AppSpacing.lg) {
        XBillSectionHeader("Active Groups", subtitle: "3 groups") {
            XBillCircularIconButton(systemImage: "plus", accessibilityLabel: "Create group") {}
        }
        XBillMetricCard(
            title: "Owed to you",
            amount: 142.50,
            icon: "arrow.down.left.circle.fill",
            direction: .positive
        )
        XBillStatusChip(text: "All settled. Nice!", icon: "checkmark.circle.fill")
    }
    .padding()
    .xbillScreenBackground()
}

//
//  XBillProfilePrimitives.swift
//  xBill
//

import SwiftUI

struct XBillInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
            Text(title)
                .font(.appBody)
                .foregroundStyle(AppColors.textSecondary)
            Spacer(minLength: AppSpacing.md)
            Text(value)
                .font(.appTitle)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(minHeight: AppSpacing.tapTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }
}

struct XBillStatsCard: View {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let value: String
    }

    let items: [Item]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                XBillInfoRow(title: item.title, value: item.value)
                    .padding(.vertical, AppSpacing.xs)
                if index < items.count - 1 {
                    Divider()
                        .overlay(AppColors.border)
                }
            }
        }
        .xbillCard(padding: AppSpacing.md)
    }
}

struct XBillFormSection<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .xbillCard(padding: AppSpacing.md)
    }
}

struct XBillPaymentHandleRow: View {
    let providerName: String
    let systemImage: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.appIcon)
                    .foregroundStyle(AppColors.primary)
                    .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
                    .background(AppColors.surfaceSoft)
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                Text(providerName)
                    .font(.appTitle)
                    .foregroundStyle(AppColors.textPrimary)
            }

            XBillTextField(placeholder: placeholder, text: $text, keyboardType: keyboardType)
                .accessibilityLabel("\(providerName) payment handle")
        }
        .accessibilityElement(children: .contain)
    }
}

struct XBillSettingsRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    var isDestructive = false
    var action: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Group {
            if let action {
                Button {
                    HapticManager.selection()
                    action()
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .frame(minHeight: AppSpacing.tapTarget)
        .accessibilityElement(children: .combine)
    }

    private var rowContent: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.appIcon)
                .foregroundStyle(foregroundColor)
                .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
                .background(backgroundColor)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(.appTitle)
                    .foregroundStyle(foregroundColor)
                if let subtitle {
                    Text(subtitle)
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: AppSpacing.md)
            trailing()
        }
    }

    private var foregroundColor: Color {
        isDestructive ? AppColors.error : AppColors.textPrimary
    }

    private var backgroundColor: Color {
        isDestructive ? AppColors.moneyNegativeBg : AppColors.surfaceSoft
    }
}

struct XBillSettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.appCaptionMedium)
            .foregroundStyle(AppColors.textTertiary)
    }
}

extension XBillSettingsRow where Trailing == XBillSettingsChevron {
    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.isDestructive = isDestructive
        self.action = action
        self.trailing = {
            XBillSettingsChevron()
        }
    }
}

extension XBillSettingsRow where Trailing == EmptyView {
    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        isDestructive: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.isDestructive = isDestructive
        self.action = action
        self.trailing = { EmptyView() }
    }
}

#Preview("Profile Primitives") {
    XBillScreenBackground {
        VStack(spacing: AppSpacing.lg) {
            XBillStatsCard(items: [
                .init(title: "Groups", value: "4"),
                .init(title: "Expenses", value: "28"),
                .init(title: "Total Paid", value: "$420.00")
            ])

            XBillFormSection {
                XBillSettingsRow(icon: "bell.badge", title: "New Expenses") {
                    Toggle("", isOn: .constant(true))
                        .labelsHidden()
                        .tint(AppColors.primary)
                }
            }
        }
        .padding(AppSpacing.lg)
    }
}

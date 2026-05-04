//
//  XBillPageHeader.swift
//  xBill
//

import SwiftUI

struct XBillPageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var showsBackButton = false
    var backAction: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = false,
        backAction: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsBackButton = showsBackButton
        self.backAction = backAction
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            if showsBackButton {
                Button {
                    backAction?()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.appTitle)
                        .foregroundStyle(AppColors.primary)
                        .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
                        .background(AppColors.surfaceSoft)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(.appH1)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                    .accessibilityIdentifier("xBill.pageHeader.title.\(title)")
                if let subtitle {
                    Text(subtitle)
                        .font(.appBody)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: AppSpacing.sm)
            trailing()
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.sm + AppSpacing.xs)
        .padding(.bottom, AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.background)
    }
}

extension XBillPageHeader where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = false,
        backAction: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            showsBackButton: showsBackButton,
            backAction: backAction,
            trailing: { EmptyView() }
        )
    }
}

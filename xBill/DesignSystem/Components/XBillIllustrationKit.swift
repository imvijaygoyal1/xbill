//
//  XBillIllustrationKit.swift
//  xBill
//

import SwiftUI

struct XBillSplitBillIllustration: View {
    var size: CGFloat = 220

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                .fill(AppColors.surfaceSoft)
                .frame(width: size, height: size * 0.72)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                        .stroke(AppColors.primary.opacity(0.16), lineWidth: 1)
                )

            billCard
                .rotationEffect(.degrees(-7))
                .offset(x: -size * 0.16, y: -size * 0.02)

            billCard
                .rotationEffect(.degrees(7))
                .offset(x: size * 0.16, y: -size * 0.05)

            HStack(spacing: -size * 0.05) {
                XBillAvatarPlaceholder(name: "A", size: size * 0.22)
                XBillAvatarPlaceholder(name: "B", size: size * 0.22)
                XBillAvatarPlaceholder(name: "C", size: size * 0.22)
            }
            .offset(y: size * 0.31)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var billCard: some View {
        VStack(alignment: .leading, spacing: size * 0.035) {
            Capsule()
                .fill(AppColors.primaryLight.opacity(0.7))
                .frame(width: size * 0.2, height: size * 0.035)
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(AppColors.border)
                    .frame(width: size * (index == 1 ? 0.32 : 0.42), height: size * 0.024)
            }
            Spacer(minLength: 0)
            HStack {
                Capsule()
                    .fill(AppColors.success)
                    .frame(width: size * 0.2, height: size * 0.035)
                Spacer()
                Image(systemName: "dollarsign")
                    .font(.system(size: size * 0.12, weight: .black, design: .rounded))
                    .foregroundStyle(AppColors.primary)
            }
        }
        .padding(size * 0.08)
        .frame(width: size * 0.48, height: size * 0.58)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .shadow(color: AppColors.primary.opacity(0.12), radius: 12, x: 0, y: 6)
    }
}

struct XBillWalletIllustration: View {
    var size: CGFloat = 200

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                .fill(AppColors.surfaceSoft)
                .frame(width: size, height: size * 0.72)
            Circle()
                .fill(AppColors.primary.opacity(0.12))
                .frame(width: size * 0.52, height: size * 0.52)
                .offset(x: size * 0.22, y: -size * 0.14)

            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                .fill(AppGradient.softPrimary)
                .frame(width: size * 0.68, height: size * 0.43)
                .offset(y: size * 0.04)

            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(AppColors.surface)
                .frame(width: size * 0.46, height: size * 0.25)
                .offset(x: size * 0.13, y: size * 0.04)

            Image(systemName: "creditcard.fill")
                .font(.system(size: size * 0.18, weight: .semibold))
                .foregroundStyle(AppColors.primary)
                .offset(x: -size * 0.18, y: size * 0.04)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct XBillEmptyStateIllustration: View {
    enum Kind {
        case friends
        case notifications
        case groups
        case expenses
        case search
        case generic(String)
    }

    var kind: Kind = .generic("sparkles")
    var size: CGFloat = 200

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                .fill(AppColors.surfaceSoft)
                .frame(width: size, height: size * 0.78)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                        .stroke(AppColors.primary.opacity(0.14), lineWidth: 1)
                )
            Circle()
                .fill(AppColors.primary.opacity(0.12))
                .frame(width: size * 0.56, height: size * 0.56)
                .offset(x: size * 0.16, y: -size * 0.14)
            foreground
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var foreground: some View {
        switch kind {
        case .friends:
            XBillFriendsIllustration(size: size * 0.9)
        case .notifications:
            Image(systemName: "bell.badge.fill")
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(AppColors.primary)
        case .groups:
            Image(systemName: "person.3.fill")
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(AppColors.primary)
        case .expenses:
            XBillReceiptIllustration(size: size * 0.86)
        case .search:
            Image(systemName: "magnifyingglass")
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(AppColors.primary)
        case .generic(let symbol):
            Image(systemName: symbol)
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(AppColors.primary)
        }
    }
}

struct XBillFriendsIllustration: View {
    var size: CGFloat = 200

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                .fill(AppColors.surfaceSoft)
                .frame(width: size, height: size * 0.72)
            HStack(spacing: -size * 0.08) {
                XBillAvatarPlaceholder(name: "A", size: size * 0.25)
                    .offset(y: size * 0.04)
                XBillAvatarPlaceholder(name: "B", size: size * 0.34)
                    .zIndex(1)
                XBillAvatarPlaceholder(name: "+", size: size * 0.25)
                    .offset(y: size * 0.04)
            }
            .overlay(
                Image(systemName: "person.badge.plus.fill")
                    .font(.system(size: size * 0.13, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .padding(size * 0.05)
                    .background(AppColors.surface)
                    .clipShape(Circle())
                    .offset(x: size * 0.29, y: size * 0.09)
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct XBillReceiptIllustration: View {
    var size: CGFloat = 200

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                .fill(AppColors.surfaceSoft)
                .frame(width: size, height: size * 0.72)
            XBillReceiptIcon(size: size * 0.52)
                .scaleEffect(1.25)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size * 0.16, weight: .semibold))
                .foregroundStyle(AppColors.success)
                .background(AppColors.surface.clipShape(Circle()))
                .offset(x: size * 0.24, y: size * 0.16)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct XBillQRCodeIllustration: View {
    var size: CGFloat = 200

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                .fill(AppColors.surfaceSoft)
                .frame(width: size, height: size * 0.78)
            XBillQRPlaceholderFrame {
                qrPattern
            }
            .frame(width: size * 0.58, height: size * 0.58)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var qrPattern: some View {
        Grid(horizontalSpacing: 5, verticalSpacing: 5) {
            ForEach(0..<5, id: \.self) { row in
                GridRow {
                    ForEach(0..<5, id: \.self) { col in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill((row + col).isMultiple(of: 2) ? Color.black : Color.clear)
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
    }
}


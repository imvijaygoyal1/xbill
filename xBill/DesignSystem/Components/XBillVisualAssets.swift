//
//  XBillVisualAssets.swift
//  xBill
//

import SwiftUI

struct XBillLogoMark: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(AppGradient.softPrimary)
            Circle()
                .fill(AppColors.textInverse.opacity(0.16))
                .frame(width: size * 0.64, height: size * 0.64)
                .offset(x: size * 0.18, y: -size * 0.2)
            Text("x")
                .font(.system(size: size * 0.48, weight: .black, design: .rounded))
                .foregroundStyle(AppColors.textInverse)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct XBillReceiptIcon: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            softContainer
            receiptShape
                .fill(AppColors.surface)
                .frame(width: size * 0.52, height: size * 0.66)
                .overlay(receiptLines.padding(size * 0.16))
                .shadow(color: AppColors.primary.opacity(0.14), radius: 8, x: 0, y: 4)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var softContainer: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(AppColors.surfaceSoft.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(AppColors.primary.opacity(0.16), lineWidth: 1)
            )
    }

    private var receiptLines: some View {
        VStack(alignment: .leading, spacing: size * 0.06) {
            Capsule().fill(AppColors.primary).frame(width: size * 0.2, height: 3)
            Capsule().fill(AppColors.border).frame(height: 3)
            Capsule().fill(AppColors.border).frame(width: size * 0.22, height: 3)
            Spacer(minLength: 0)
            Capsule().fill(AppColors.success).frame(width: size * 0.24, height: 4)
        }
    }

    private var receiptShape: some Shape {
        UnevenRoundedRectangle(
            topLeadingRadius: AppRadius.sm,
            bottomLeadingRadius: AppRadius.sm,
            bottomTrailingRadius: AppRadius.sm,
            topTrailingRadius: AppRadius.sm,
            style: .continuous
        )
    }
}

struct XBillWalletIllustration: View {
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            Circle()
                .fill(AppColors.textInverse.opacity(0.14))
                .frame(width: size, height: size)
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(AppColors.textInverse)
                .frame(width: size * 0.7, height: size * 0.48)
                .offset(y: size * 0.06)
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(AppColors.primaryLight)
                .frame(width: size * 0.44, height: size * 0.28)
                .offset(x: size * 0.16, y: size * 0.06)
            Circle()
                .fill(AppColors.primaryDark)
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: size * 0.29, y: size * 0.06)
            Image(systemName: "creditcard.fill")
                .font(.system(size: size * 0.22, weight: .semibold))
                .foregroundStyle(AppColors.primary)
                .offset(x: -size * 0.17, y: size * 0.05)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct XBillSplitBillIllustration: View {
    var size: CGFloat = 180

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                .fill(AppColors.textInverse.opacity(0.14))
                .frame(width: size, height: size * 0.76)

            billCard
                .rotationEffect(.degrees(-7))
                .offset(x: -size * 0.16, y: size * 0.01)

            billCard
                .rotationEffect(.degrees(7))
                .offset(x: size * 0.16, y: -size * 0.02)

            HStack(spacing: -size * 0.05) {
                XBillAvatarPlaceholder(name: "A", size: size * 0.24)
                XBillAvatarPlaceholder(name: "B", size: size * 0.24)
                XBillAvatarPlaceholder(name: "C", size: size * 0.24)
            }
            .offset(y: size * 0.32)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var billCard: some View {
        VStack(alignment: .leading, spacing: size * 0.035) {
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(AppColors.primaryLight.opacity(0.55))
                .frame(width: size * 0.2, height: size * 0.035)
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(AppColors.border)
                    .frame(width: size * (index == 1 ? 0.34 : 0.42), height: size * 0.025)
            }
            Spacer(minLength: 0)
            HStack {
                Capsule()
                    .fill(AppColors.success)
                    .frame(width: size * 0.2, height: size * 0.035)
                Spacer()
                Text("$")
                    .font(.system(size: size * 0.16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.primary)
            }
        }
        .padding(size * 0.08)
        .frame(width: size * 0.48, height: size * 0.62)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
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
    var size: CGFloat = 112

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous)
                .fill(AppColors.surfaceSoft)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous)
                        .stroke(AppColors.primary.opacity(0.14), lineWidth: 1)
                )
            Circle()
                .fill(AppColors.primary.opacity(0.12))
                .frame(width: size * 0.62, height: size * 0.62)
                .offset(x: size * 0.15, y: -size * 0.14)
            foreground
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var foreground: some View {
        switch kind {
        case .friends:
            HStack(spacing: -size * 0.08) {
                XBillAvatarPlaceholder(name: "A", size: size * 0.32)
                XBillAvatarPlaceholder(name: "B", size: size * 0.38)
                XBillAvatarPlaceholder(name: "+", size: size * 0.32)
            }
        case .notifications:
            Image(systemName: "bell.badge.fill")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(AppColors.primary)
        case .groups:
            Image(systemName: "person.3.fill")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(AppColors.primary)
        case .expenses:
            XBillReceiptIcon(size: size * 0.62)
        case .search:
            Image(systemName: "magnifyingglass")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(AppColors.primary)
        case .generic(let symbol):
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(AppColors.primary)
        }
    }
}

struct XBillAvatarPlaceholder: View {
    var name: String
    var size: CGFloat = AppSpacing.tapTarget

    private var initials: String {
        let value = name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
        return value.isEmpty ? "?" : value.uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(AppGradient.softPrimary)
            Circle()
                .fill(AppColors.textInverse.opacity(0.15))
                .frame(width: size * 0.64, height: size * 0.64)
                .offset(x: size * 0.18, y: -size * 0.18)
            Text(initials)
                .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textInverse)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct XBillCategoryIcon: View {
    let category: Expense.Category
    var size: CGFloat = XBillIcon.categorySize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(AppColors.surfaceSoft)
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(category.categoryBackground.opacity(0.9))
            Image(systemName: category.symbolName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(AppColors.primary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct XBillQRPlaceholderFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .fill(Color.white)
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
            cornerMarks
            content
                .padding(AppSpacing.lg)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var cornerMarks: some View {
        GeometryReader { proxy in
            let length = min(proxy.size.width, proxy.size.height) * 0.13
            let inset = min(proxy.size.width, proxy.size.height) * 0.08
            ZStack {
                QRCorner(length: length).stroke(Color.black.opacity(0.3), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: length, height: length)
                    .position(x: inset + length / 2, y: inset + length / 2)
                QRCorner(length: length).stroke(Color.black.opacity(0.3), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: length, height: length)
                    .rotationEffect(.degrees(90))
                    .position(x: proxy.size.width - inset - length / 2, y: inset + length / 2)
                QRCorner(length: length).stroke(Color.black.opacity(0.3), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: length, height: length)
                    .rotationEffect(.degrees(180))
                    .position(x: proxy.size.width - inset - length / 2, y: proxy.size.height - inset - length / 2)
                QRCorner(length: length).stroke(Color.black.opacity(0.3), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: length, height: length)
                    .rotationEffect(.degrees(270))
                    .position(x: inset + length / 2, y: proxy.size.height - inset - length / 2)
            }
        }
    }
}

private struct QRCorner: Shape {
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

extension Expense.Category {
    var symbolName: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "airplane"
        case .accommodation: return "house.fill"
        case .entertainment: return "popcorn.fill"
        case .utilities: return "bolt.fill"
        case .shopping: return "bag.fill"
        case .health: return "cross.case.fill"
        case .other: return "sparkles"
        }
    }
}

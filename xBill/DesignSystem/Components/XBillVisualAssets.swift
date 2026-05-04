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

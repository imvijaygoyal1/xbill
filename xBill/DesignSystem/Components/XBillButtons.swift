//
//  XBillButtons.swift
//  xBill
//

import SwiftUI

private struct XBillButtonBase: View {
    let title: String
    var icon: String?
    var background: Color
    var foreground: Color
    var border: Color = .clear
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button {
            guard !isLoading, !isDisabled else { return }
            HapticManager.impact(.medium)
            action()
        } label: {
            HStack(spacing: AppSpacing.sm) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else {
                    if let icon { Image(systemName: icon) }
                    Text(title)
                }
            }
            .font(.appTitle)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppSpacing.controlHeight)
            .background(isDisabled ? AppColors.surfaceSoft : background)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isDisabled)
        .opacity(isLoading || isDisabled ? 0.72 : 1)
    }
}

struct XBillPrimaryButton: View {
    let title: String
    var icon: String?
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        XBillButtonBase(title: title, icon: icon, background: AppColors.primary, foreground: AppColors.textInverse, isLoading: isLoading, isDisabled: isDisabled, action: action)
    }
}

struct XBillSecondaryButton: View {
    let title: String
    var icon: String?
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        XBillButtonBase(title: title, icon: icon, background: AppColors.surface, foreground: AppColors.primary, border: AppColors.border, isLoading: isLoading, isDisabled: isDisabled, action: action)
    }
}

struct XBillBlackButton: View {
    let title: String
    var icon: String?
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        XBillButtonBase(title: title, icon: icon, background: AppColors.blackNav, foreground: AppColors.textInverse, isLoading: isLoading, isDisabled: isDisabled, action: action)
    }
}

struct XBillPillButton: View {
    let title: String
    var icon: String?
    var style: Style = .primary
    var isDisabled = false
    let action: () -> Void

    enum Style {
        case primary
        case secondary
    }

    var body: some View {
        Button {
            guard !isDisabled else { return }
            HapticManager.selection()
            action()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(.appCaptionMedium)
            .foregroundStyle(foreground)
            .padding(.horizontal, AppSpacing.md)
            .frame(minHeight: AppSpacing.tapTarget)
            .background(background)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.72 : 1)
    }

    private var background: Color {
        switch style {
        case .primary: AppColors.primary
        case .secondary: AppColors.surfaceSoft
        }
    }

    private var foreground: Color {
        switch style {
        case .primary: AppColors.textInverse
        case .secondary: AppColors.textSecondary
        }
    }

    private var border: Color {
        switch style {
        case .primary: .clear
        case .secondary: AppColors.border
        }
    }
}

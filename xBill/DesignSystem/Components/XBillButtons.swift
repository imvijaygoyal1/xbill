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

//
//  XBillButtons.swift
//  xBill
//

import SwiftUI

/// Glass fill for an enabled button, flat fill for a disabled one.
private struct XBillButtonSurface: ViewModifier {
    let background: Color
    let isDisabled: Bool
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
        if isDisabled {
            content.background(AppColors.surfaceSoft).clipShape(shape)
        } else {
            content.liquidGlassButton(tint: background, fallback: background, in: shape)
        }
    }
}

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
            .foregroundStyle(isDisabled ? AppColors.textSecondary : foreground)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppSpacing.controlHeight)
            // Disabled stays deliberately flat. Glass reads as "live and touchable", so a
            // disabled control rendered in glass invites taps that do nothing — the opposite of
            // the affordance E-1/E-2 established for this button.
            .modifier(XBillButtonSurface(background: background, isDisabled: isDisabled))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(isDisabled ? AppColors.border : border, lineWidth: 1)
            )
            // Device-reported: taps at the left and right of the button did nothing while the
            // middle worked. With `.buttonStyle(.plain)` the hit region follows the label's
            // **content** — here a centred `Text` — so `.frame(maxWidth: .infinity)` widened the
            // painted area without widening the tappable one. Neither `.background` nor
            // `.glassEffect` contributes a hit region. This affects every primary and secondary
            // CTA in the app and predates the glass work.
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isDisabled)
        .opacity(isLoading ? 0.72 : 1)
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

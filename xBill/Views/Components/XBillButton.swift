import SwiftUI

enum XBillButtonStyle {
    case primary
    case secondary
    case ghost
    case destructive
}

struct XBillButton: View {
    let title: String
    var style: XBillButtonStyle = .primary
    var isLoading: Bool = false
    let action: () -> Void

    private var bgColor: Color {
        switch style {
        case .primary:     return .brandPrimary
        case .secondary:   return .clear
        case .ghost:       return .clear
        case .destructive: return .moneyNegative
        }
    }
    private var fgColor: Color {
        switch style {
        case .primary:     return .textInverse
        case .secondary:   return .brandPrimary
        case .ghost:       return .brandPrimary
        case .destructive: return .textInverse
        }
    }
    private var borderColor: Color {
        switch style {
        case .secondary: return .brandPrimary
        default:         return .clear
        }
    }

    var body: some View {
        Button(action: {
            HapticManager.impact(.medium)
            action()
        }) {
            ZStack {
                if isLoading {
                    ProgressView().tint(fgColor)
                } else {
                    Text(title)
                        .font(.xbillButtonLarge)
                        .foregroundStyle(fgColor)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: XBillRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: XBillRadius.md)
                    .stroke(borderColor, lineWidth: 1.5)
            )
        }
        .disabled(isLoading)
    }
}

#Preview {
    VStack(spacing: 12) {
        XBillButton(title: "Add Expense", style: .primary) {}
        XBillButton(title: "Cancel", style: .secondary) {}
        XBillButton(title: "Sign out", style: .ghost) {}
        XBillButton(title: "Delete", style: .destructive) {}
        XBillButton(title: "Saving…", style: .primary, isLoading: true) {}
    }
    .padding()
}

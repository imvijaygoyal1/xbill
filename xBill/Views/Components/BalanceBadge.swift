import SwiftUI

/// Compact balance indicator: green when owed money, red when owing money.
struct BalanceBadge: View {
    let amount: Decimal
    let currency: String

    private var isZero: Bool { amount == .zero }
    private var isPositive: Bool { amount > .zero }

    private var label: String {
        if isZero { return "Settled" }
        let formatted = abs(amount).formatted(currencyCode: currency)
        return isPositive ? "Gets \(formatted)" : "Owes \(formatted)"
    }

    private var badgeColor: Color {
        if isZero    { return .secondary }
        if isPositive { return .green }
        return .red
    }

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(badgeForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .liquidGlassButton(
                fallback: isZero ? Color(.systemGray5) : badgeColor,
                in: Capsule()
            )
    }

    private var badgeForeground: Color {
        if #available(iOS 26, *) {
            return isZero ? .secondary : badgeColor
        }
        return isZero ? .secondary : .white
    }
}

#Preview {
    VStack(spacing: 12) {
        BalanceBadge(amount: 42.50, currency: "USD")
        BalanceBadge(amount: -17.00, currency: "USD")
        BalanceBadge(amount: .zero, currency: "USD")
    }
    .padding()
}

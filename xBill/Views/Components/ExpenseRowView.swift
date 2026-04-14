import SwiftUI

struct ExpenseRowView: View {
    let expense: Expense
    let members: [User]
    var showAmountBadge: Bool = false

    private func name(for id: UUID) -> String {
        members.first(where: { $0.id == id })?.displayName ?? "Someone"
    }

    var body: some View {
        HStack(spacing: XBillSpacing.md) {
            CategoryIconView(category: expense.category)

            VStack(alignment: .leading, spacing: 3) {
                Text(expense.title)
                    .font(.xbillBodyMedium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("\(name(for: expense.payerID)) paid · \(expense.createdAt.relativeFormatted)")
                    .font(.xbillCaption)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            if showAmountBadge {
                AmountBadge(amount: expense.amount, direction: .total, currency: expense.currency)
            } else {
                Text(expense.amount.formatted(currencyCode: expense.currency))
                    .font(.xbillSmallAmount)
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .padding(.vertical, XBillSpacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(expense.title), paid by \(name(for: expense.payerID)), \(expense.amount.formatted(currencyCode: expense.currency))")
    }
}

#Preview {
    List {
        ExpenseRowView(
            expense: Expense(
                id: UUID(), groupID: UUID(), title: "Team Lunch",
                amount: 87.40, currency: "USD", payerID: UUID(),
                category: .food, notes: nil, receiptURL: nil,
                recurrence: .none, createdAt: Date()
            ),
            members: [],
            showAmountBadge: true
        )
        .listRowBackground(Color.bgCard)
    }
}

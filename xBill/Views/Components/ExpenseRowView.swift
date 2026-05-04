//
//  ExpenseRowView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct ExpenseRowView: View {
    let expense: Expense
    let members: [User]
    var showAmountBadge: Bool = false

    private func name(for id: UUID) -> String {
        members.first(where: { $0.id == id })?.displayName ?? "Someone"
    }

    var body: some View {
        XBillExpenseRow(expense: expense, members: members, showAmountBadge: showAmountBadge)
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

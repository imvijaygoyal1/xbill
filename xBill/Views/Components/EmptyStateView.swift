//
//  EmptyStateView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        if let actionLabel, let action {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                Text(message)
            } actions: {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                Text(message)
            }
        }
    }
}

#Preview {
    EmptyStateView(
        icon: "person.3.fill",
        title: "No Groups Yet",
        message: "Create a group to start splitting expenses with friends.",
        actionLabel: "Create Group",
        action: { }
    )
}

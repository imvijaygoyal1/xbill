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
    var illustration: XBillEmptyStateIllustration.Kind? = nil

    var body: some View {
        XBillEmptyState(
            icon: icon,
            title: title,
            message: message,
            actionLabel: actionLabel,
            action: action,
            illustration: illustration
        )
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

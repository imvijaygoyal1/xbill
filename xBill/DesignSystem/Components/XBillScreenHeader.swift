//
//  XBillScreenHeader.swift
//  xBill
//

import SwiftUI

struct XBillScreenHeader: View {
    let title: String
    var subtitle: String?
    var trailingSystemImage: String?
    var trailingAccessibilityLabel: String?
    var trailingAction: (() -> Void)?

    var body: some View {
        XBillPageHeader(title: title, subtitle: subtitle) {
            if let trailingSystemImage, let trailingAction {
                XBillCircularIconButton(
                    systemImage: trailingSystemImage,
                    accessibilityLabel: trailingAccessibilityLabel ?? title,
                    action: trailingAction
                )
            }
        }
    }
}

#Preview("Screen Header") {
    XBillScreenBackground {
        VStack {
            XBillScreenHeader(
                title: "Friends",
                subtitle: "Track balances outside groups.",
                trailingSystemImage: "person.badge.plus",
                trailingAccessibilityLabel: "Add Friend",
                trailingAction: {}
            )
            Spacer()
        }
    }
}

#Preview("Screen Header Dark") {
    XBillScreenBackground {
        VStack {
            XBillScreenHeader(
                title: "Friends",
                subtitle: "Track balances outside groups.",
                trailingSystemImage: "person.badge.plus",
                trailingAccessibilityLabel: "Add Friend",
                trailingAction: {}
            )
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

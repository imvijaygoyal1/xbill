//
//  XBillDetailHeader.swift
//  xBill
//

import SwiftUI

struct XBillDetailHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let backAction: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        XBillPageHeader(
            title: title,
            subtitle: subtitle,
            showsBackButton: true,
            backAction: backAction,
            trailing: trailing
        )
    }
}

extension XBillDetailHeader where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        backAction: @escaping () -> Void
    ) {
        self.init(title: title, subtitle: subtitle, backAction: backAction) {
            EmptyView()
        }
    }
}

#Preview("Detail Header") {
    XBillScreenBackground {
        VStack {
            XBillDetailHeader(
                title: "Add Friend",
                subtitle: "Find people by email, QR link, or contacts.",
                backAction: {}
            )
            Spacer()
        }
    }
}

#Preview("Detail Header Dark") {
    XBillScreenBackground {
        VStack {
            XBillDetailHeader(
                title: "Add Friend",
                subtitle: "Find people by email, QR link, or contacts.",
                backAction: {}
            )
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

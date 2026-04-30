//
//  GroupChipView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct GroupChipView: View {
    let group: BillGroup

    var body: some View {
        VStack(alignment: .leading, spacing: XBillSpacing.sm) {
            Text(group.emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.brandSurface)
                .clipShape(Circle())

            Text(group.name)
                .font(.xbillLabel)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Text(group.currency)
                .font(.xbillCaption)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(XBillSpacing.md)
        .frame(width: 110)
        .asSharpCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.name) group, \(group.currency)")
        .accessibilityAddTraits(.isButton)
    }
}

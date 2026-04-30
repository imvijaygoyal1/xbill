//
//  XBillCard.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct XBillCard<Content: View>: View {
    var padding: CGFloat = XBillSpacing.base
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .asSharpCard()
    }
}

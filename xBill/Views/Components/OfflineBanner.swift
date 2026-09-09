//
//  OfflineBanner.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: XBillSpacing.sm) {
            // ICON-06: the banner states an ONGOING condition, and a pulsing glyph is how iOS
            // distinguishes "still true" from "happened once". iOS 17, so no availability guard.
            Image(systemName: "wifi.slash")
                .font(.caption.bold())
                .symbolEffect(.pulse)
            Text("Offline · Showing cached data")
                .font(.caption.bold())
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.orange)
    }
}

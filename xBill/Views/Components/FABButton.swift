//
//  FABButton.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct FABButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.impact(.medium)
            action()
        }) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.textInverse)
                .frame(width: XBillIcon.fabSize, height: XBillIcon.fabSize)
                .background(Color.brandPrimary)
                .clipShape(Circle())
                // Clay: hard offset shadow on FAB instead of soft glow
                .shadow(color: .black.opacity(0.25), radius: 0, x: -3, y: 3)
        }
        .buttonStyle(ClayButtonStyle())
    }
}

#Preview {
    FABButton {}
        .padding()
}

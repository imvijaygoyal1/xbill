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
        XBillFloatingAddButton(action: action)
    }
}

#Preview {
    FABButton {}
        .padding()
}

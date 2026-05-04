//
//  XBillScreenBackground.swift
//  xBill
//

import SwiftUI

struct XBillScreenBackground<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            content()
        }
    }
}

extension View {
    func xbillScreenBackground() -> some View {
        background(AppColors.background.ignoresSafeArea())
    }
}

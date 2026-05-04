//
//  XBillScrollView.swift
//  xBill
//

import SwiftUI

struct XBillScrollView<Content: View>: View {
    var showsIndicators = true
    var horizontalPadding: CGFloat = AppSpacing.lg
    var bottomPadding: CGFloat = AppSpacing.floatingActionBottomPadding
    var spacing: CGFloat = AppSpacing.lg
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: showsIndicators) {
            LazyVStack(alignment: .leading, spacing: spacing) {
                content()
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, bottomPadding)
        }
        .background(AppColors.background)
    }
}


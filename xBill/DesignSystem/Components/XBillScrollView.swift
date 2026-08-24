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
            // `VStack`, NOT `LazyVStack` (UI-01).
            //
            // Manage Group scrolled endlessly — three short sections and a 10-icon grid, and the
            // scroll view believed it was far taller, so swiping ran off into blank space. The
            // cause is a `LazyVGrid` (the icon picker) inside a `LazyVStack`: the lazy stack
            // cannot resolve the grid's height eagerly and over-reports its own.
            //
            // Measured, not reasoned: a UI probe that swipes past the end and asserts some content
            // is still on screen **failed before this change and passed after**, with nothing else
            // altered.
            //
            // Laziness bought nothing here. Every screen using this container renders a handful of
            // sections, or a `ForEach` over user data measured in dozens — not the thousands of
            // rows `LazyVStack` exists for. This is the **second** layout defect traced to this
            // component; `RC-4` was the first (mid-animation re-layout in `EmailAuthView`).
            VStack(alignment: .leading, spacing: spacing) {
                content()
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, bottomPadding)
        }
        .background(AppColors.background)
    }
}


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
            // scroll view believed it was far taller, so swiping ran into blank space. Swapping
            // this one line fixes it, measured by a UI probe that swipes past the end and asserts
            // some content is still on screen: it **fails against `LazyVStack` and passes against
            // `VStack`**, with nothing else changed.
            //
            // ⚠️ **The precise trigger is NOT established.** The first explanation written here —
            // "a `LazyVGrid` inside a `LazyVStack`" — is **wrong**: `CreateGroupView` has the same
            // icon grid in the same container and its probe passes even against `LazyVStack`.
            // Something else about Manage Group is required. What is established is only that
            // removing the laziness fixes it and regresses nothing.
            //
            // Laziness bought nothing here. Every screen using this container renders a handful of
            // sections, or a `ForEach` over user data measured in dozens — not the thousands of
            // rows `LazyVStack` exists for. This is the **second** layout defect traced to this
            // component; `RC-4` was the first (mid-animation re-layout in `EmailAuthView`).
            //
            // Swept: Manage Group (was broken, now fixed), Create Group (never broken) and Home
            // (two `LazyVStack`s of its own, never broken) all pass.
            VStack(alignment: .leading, spacing: spacing) {
                content()
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, bottomPadding)
        }
        .background(AppColors.background)
    }
}


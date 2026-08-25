//
//  XBillScrollView.swift
//  xBill
//

import SwiftUI

struct XBillScrollView<Content: View>: View {
    /// Names this scroll view in the DEBUG content-height log.
    var probeLabel: String = "unnamed"
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
            // DEBUG-only measurement for the Add Friend report (UI-02). Reads the content's own
            // height and compares it with the viewport. A `.background` overlay does not
            // participate in layout, so measuring cannot itself change what is measured.
            .modifier(ScrollContentProbe(label: probeLabel))
        }
        .background(AppColors.background)
    }
}

/// Logs how tall a scroll view's content actually is, against the screen it sits in.
///
/// A scroll view that "scrolls endlessly" is reporting content far taller than it has; this says
/// by how much, which is the thing no amount of reading the view hierarchy established. DEBUG only
/// and compiled out of Release.
private struct ScrollContentProbe: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        #if DEBUG
        content.background(
            GeometryReader { proxy in
                Color.clear.onAppear {
                    let screen = UIScreen.main.bounds.height
                    AppDiagnostics.log(.lifecycle, "scrollContentHeight", [
                        ("screen", label),
                        ("contentHeight", Int(proxy.size.height)),
                        ("viewportHeight", Int(screen)),
                        ("ratio", String(format: "%.1fx", proxy.size.height / max(screen, 1)))
                    ])
                }
            }
        )
        #else
        content
        #endif
    }
}

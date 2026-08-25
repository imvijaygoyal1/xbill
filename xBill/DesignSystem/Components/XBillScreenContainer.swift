//
//  XBillScreenContainer.swift
//  xBill
//

import SwiftUI

struct XBillScreenContainer<Content: View, StickyBottom: View>: View {
    enum Mode {
        case scroll
        case fixed
    }

    var mode: Mode = .scroll
    /// Forwarded to the DEBUG content-height probe so the log names the screen.
    var probeLabel: String = "unnamed"
    var horizontalPadding: CGFloat = AppSpacing.lg
    var contentSpacing: CGFloat = AppSpacing.lg
    var bottomPadding: CGFloat = AppSpacing.floatingActionBottomPadding
    @ViewBuilder var content: () -> Content
    @ViewBuilder var stickyBottom: () -> StickyBottom

    var body: some View {
        XBillScreenBackground {
            Group {
                switch mode {
                case .scroll:
                    XBillScrollView(
                        probeLabel: probeLabel,
                        horizontalPadding: horizontalPadding,
                        bottomPadding: bottomPadding,
                        spacing: contentSpacing,
                        content: content
                    )
                case .fixed:
                    VStack(alignment: .leading, spacing: contentSpacing) {
                        content()
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, bottomPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            // UI-02. Applied ONLY when there is a real sticky bottom.
            //
            // `safeAreaInset` was attached unconditionally, so every screen without one still got
            // an inset built from an `EmptyView`. That inset is added to the scroll view's
            // scrollable extent from OUTSIDE its content — which is why Add Friend scrolled into
            // blank space while its content measured **shorter than the screen**:
            //
            //     screen=AddFriend contentHeight=826 viewportHeight=874 ratio=0.9x
            //
            // A 0.9x content ratio cannot scroll. The extra extent was this inset, and no amount
            // of reading the view's own body could show it, because it is not in the view's body.
            .modifier(OptionalBottomInset(content: stickyBottom))
        }
    }
}

extension XBillScreenContainer where StickyBottom == EmptyView {
    init(
        mode: Mode = .scroll,
        probeLabel: String = "unnamed",
        horizontalPadding: CGFloat = AppSpacing.lg,
        contentSpacing: CGFloat = AppSpacing.lg,
        bottomPadding: CGFloat = AppSpacing.floatingActionBottomPadding,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            mode: mode,
            probeLabel: probeLabel,
            horizontalPadding: horizontalPadding,
            contentSpacing: contentSpacing,
            bottomPadding: bottomPadding,
            content: content,
            stickyBottom: { EmptyView() }
        )
    }
}

/// Applies `safeAreaInset(edge: .bottom)` only when the supplied view is not `EmptyView`.
///
/// An inset built from an empty view is not free: it still contributes to a scroll view's
/// scrollable extent, producing dead space below content that is already shorter than the screen.
private struct OptionalBottomInset<Inset: View>: ViewModifier {
    @ViewBuilder let content: () -> Inset

    func body(content view: Content) -> some View {
        if Inset.self == EmptyView.self {
            view
        } else {
            view.safeAreaInset(edge: .bottom, spacing: 0) { content() }
        }
    }
}

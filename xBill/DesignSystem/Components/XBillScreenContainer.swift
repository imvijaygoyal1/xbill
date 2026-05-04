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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                stickyBottom()
            }
        }
    }
}

extension XBillScreenContainer where StickyBottom == EmptyView {
    init(
        mode: Mode = .scroll,
        horizontalPadding: CGFloat = AppSpacing.lg,
        contentSpacing: CGFloat = AppSpacing.lg,
        bottomPadding: CGFloat = AppSpacing.floatingActionBottomPadding,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            mode: mode,
            horizontalPadding: horizontalPadding,
            contentSpacing: contentSpacing,
            bottomPadding: bottomPadding,
            content: content,
            stickyBottom: { EmptyView() }
        )
    }
}

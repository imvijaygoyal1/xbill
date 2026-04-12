import SwiftUI

struct XBillCard<Content: View>: View {
    var padding: CGFloat = XBillSpacing.base
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XBillRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: XBillRadius.lg)
                    .stroke(Color.separator, lineWidth: 0.5)
            )
    }
}

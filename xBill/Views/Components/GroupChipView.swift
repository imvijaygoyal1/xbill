import SwiftUI

struct GroupChipView: View {
    let group: BillGroup

    var body: some View {
        VStack(alignment: .leading, spacing: XBillSpacing.sm) {
            Text(group.emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.brandSurface)
                .clipShape(Circle())

            Text(group.name)
                .font(.xbillLabel)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Text(group.currency)
                .font(.xbillCaption)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(XBillSpacing.md)
        .frame(width: 110)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XBillRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XBillRadius.lg)
                .stroke(Color.separator, lineWidth: 0.5)
        )
    }
}

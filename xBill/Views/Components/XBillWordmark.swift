import SwiftUI

struct XBillWordmark: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("x")
                .font(.system(size: 22, weight: .heavy, design: .default))
                .foregroundStyle(Color.brandPrimary)
            Text("Bill")
                .font(.system(size: 22, weight: .heavy, design: .default))
                .foregroundStyle(Color.brandPrimary)
        }
        .tracking(-0.8)
        .kerning(-0.5)
    }
}

#Preview {
    XBillWordmark()
}

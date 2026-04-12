import SwiftUI

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: XBillSpacing.sm) {
            Image(systemName: "wifi.slash")
                .font(.caption.bold())
            Text("Offline · Showing cached data")
                .font(.caption.bold())
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.orange)
    }
}

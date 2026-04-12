import SwiftUI

struct FABButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.impact(.medium)
            action()
        }) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.textInverse)
                .frame(width: XBillIcon.fabSize, height: XBillIcon.fabSize)
                .background(Color.brandPrimary)
                .clipShape(Circle())
                .shadow(color: Color.brandPrimary.opacity(0.35), radius: 8, x: 0, y: 4)
        }
    }
}

#Preview {
    FABButton {}
        .padding()
}

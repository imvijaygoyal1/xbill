import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    private var emptyButtonForeground: Color {
        if #available(iOS 26, *) { return .accentColor }
        return .white
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.bold())
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.subheadline.bold())
                        .foregroundStyle(emptyButtonForeground)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .liquidGlassButton(fallback: Color.accentColor, in: Capsule())
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    EmptyStateView(
        icon: "person.3.fill",
        title: "No Groups Yet",
        message: "Create a group to start splitting expenses with friends.",
        actionLabel: "Create Group",
        action: { }
    )
}

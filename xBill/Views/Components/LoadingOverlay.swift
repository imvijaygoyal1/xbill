import SwiftUI

struct LoadingOverlay: View {
    var message: String = "Loading…"

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).opacity(0.85))
    }
}

/// View modifier that overlays a loading state on top of any view.
struct LoadingModifier: ViewModifier {
    let isLoading: Bool
    var message: String = "Loading…"

    func body(content: Content) -> some View {
        ZStack {
            content
            if isLoading {
                LoadingOverlay(message: message)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

extension View {
    func loadingOverlay(_ isLoading: Bool, message: String = "Loading…") -> some View {
        modifier(LoadingModifier(isLoading: isLoading, message: message))
    }
}

#Preview {
    LoadingOverlay(message: "Saving expense…")
}

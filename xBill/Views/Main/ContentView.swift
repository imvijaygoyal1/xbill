import SwiftUI

struct ContentView: View {
    @Bindable var authVM: AuthViewModel

    var body: some View {
        ZStack {
            if authVM.isInPasswordRecovery {
                ResetPasswordView(authVM: authVM)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if authVM.currentUser != nil {
                MainTabView(authVM: authVM)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                AuthView(vm: authVM)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: authVM.isInPasswordRecovery)
        .animation(.easeInOut(duration: 0.4), value: authVM.currentUser != nil)
    }
}

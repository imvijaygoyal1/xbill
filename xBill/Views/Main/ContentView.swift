import SwiftUI

struct ContentView: View {
    @Bindable var authVM: AuthViewModel
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            XBillTheme.background.ignoresSafeArea()

            if authVM.isInPasswordRecovery {
                ResetPasswordView(authVM: authVM)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if authVM.currentUser != nil {
                if hasCompletedOnboarding {
                    MainTabView(authVM: authVM)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal:   .move(edge: .trailing).combined(with: .opacity)
                        ))
                } else {
                    OnboardingView {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            hasCompletedOnboarding = true
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
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
        .animation(.easeInOut(duration: 0.4), value: hasCompletedOnboarding)
    }
}

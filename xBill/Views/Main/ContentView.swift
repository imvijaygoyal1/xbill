//
//  ContentView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @Bindable var authVM: AuthViewModel
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var lockService = AppLockService.shared
    @State private var sampleDataError: AppError?
    // Owned here so onTrySampleData can write into the same instance that MainTabView reads.
    @State private var homeVM = HomeViewModel()

    var body: some View {
        ZStack {
            XBillTheme.background.ignoresSafeArea()

            if authVM.isInPasswordRecovery {
                ResetPasswordView(authVM: authVM)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if authVM.currentUser != nil {
                if hasCompletedOnboarding {
                    MainTabView(authVM: authVM, homeVM: homeVM)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal:   .move(edge: .trailing).combined(with: .opacity)
                        ))
                } else {
                    OnboardingView {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            hasCompletedOnboarding = true
                        }
                    } onTrySampleData: {
                        guard let userID = authVM.currentUser?.id else { return }
                        do {
                            try await homeVM.createSampleData(userID: userID)
                            // Refresh the live VM so groups appear immediately on transition.
                            await homeVM.loadAll()
                        } catch {
                            sampleDataError = AppError.from(error)
                        }
                        withAnimation(.easeInOut(duration: 0.4)) {
                            hasCompletedOnboarding = true
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .move(edge: .bottom).combined(with: .opacity)
                    ))
                }

                if lockService.isLocked {
                    AppLockView()
                        .transition(.opacity)
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
        .animation(.easeInOut(duration: 0.3), value: lockService.isLocked)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                lockService.lock()
            }
        }
        .alert("Sample Data Error", isPresented: Binding(
            get: { sampleDataError != nil },
            set: { if !$0 { sampleDataError = nil } }
        )) {
            Button("OK") { sampleDataError = nil }
        } message: {
            Text(sampleDataError?.errorDescription ?? "Could not create sample data.")
        }
    }
}

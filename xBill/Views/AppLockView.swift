//
//  AppLockView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct AppLockView: View {
    @State private var lockService = AppLockService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            Color.brandPrimary.ignoresSafeArea()

            VStack(spacing: XBillSpacing.xxxl) {
                Spacer()

                VStack(spacing: XBillSpacing.xl) {
                    Image(systemName: lockService.lockIconName)
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.9))
                        .accessibilityHidden(true)

                    VStack(spacing: XBillSpacing.sm) {
                        XBillWordmark()
                            .colorScheme(.dark)

                        Text("Locked")
                            .font(.xbillLargeTitle)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Spacer()

                Button {
                    Task {
                        guard !isAuthenticating else { return }
                        isAuthenticating = true
                        await lockService.authenticate()
                        isAuthenticating = false
                    }
                } label: {
                    Label(lockService.unlockLabel, systemImage: lockService.lockIconName)
                        .font(.xbillButtonLarge)
                        .foregroundStyle(Color.brandPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: XBillRadius.md))
                        .padding(.horizontal, XBillSpacing.xl)
                }
                .buttonStyle(ClayButtonStyle())
                .padding(.bottom, XBillSpacing.xxxl)
            }
        }
        // Auto-authenticate ONLY while the app is actually frontmost.
        //
        // `lock()` runs on `.background`, so `AppLockView` is inserted into the hierarchy while the
        // app is being backgrounded — and a bare `.task` fired `authenticate()` right then.
        // `LAContext.evaluatePolicy` presents the system biometric prompt, and **that wakes the
        // screen**: a phone sitting idle on a desk would light up and ask for Face ID with nobody
        // touching it.
        //
        // Keyed on `scenePhase` instead, so the prompt appears when the user actually returns.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            guard !isAuthenticating else { return }
            isAuthenticating = true
            await lockService.authenticate()
            isAuthenticating = false
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    AppLockView()
}

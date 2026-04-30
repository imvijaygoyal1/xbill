//
//  AppLockView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct AppLockView: View {
    @State private var lockService = AppLockService.shared

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
                    Task { await lockService.authenticate() }
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
        .task { await lockService.authenticate() }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    AppLockView()
}

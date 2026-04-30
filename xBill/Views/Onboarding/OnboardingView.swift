//
//  OnboardingView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

// MARK: - OnboardingView
// Shown once after first sign-in. Each page has a distinct clay swatch background.
// Completion persisted via @AppStorage so it only shows once per install.

struct OnboardingView: View {
    var onComplete: () -> Void
    var onTrySampleData: (() async -> Void)? = nil

    @State private var currentPage = 0
    @State private var isCreatingSample = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "dollarsign.circle.fill",
            title: "Welcome to xBill",
            description: "The easiest way to split expenses with friends, roommates, and travel buddies — no awkward money talks required.",
            swatchColor: Color.clayUbe,          // Ube 800 — brand purple
            onSwatch: true
        ),
        OnboardingPage(
            icon: "person.3.fill",
            title: "Create Groups",
            description: "Organise expenses by trip, household, or occasion. Everyone in the group can add expenses and see what they owe at a glance.",
            swatchColor: Color.clayMatchaDark,   // Matcha 800 — deep green
            onSwatch: true
        ),
        OnboardingPage(
            icon: "camera.viewfinder",
            title: "Scan Receipts",
            description: "Point your camera at any receipt. xBill reads the items, splits the total, and assigns shares automatically using on-device AI.",
            swatchColor: Color.claySlushieDark,  // Slushie 800 — deep teal
            onSwatch: true
        ),
        OnboardingPage(
            icon: "chart.bar.fill",
            title: "Stay Balanced",
            description: "See live balances across all your groups. Settle up with one tap and track your spending history over time.",
            swatchColor: Color.clayLemon,        // Lemon 500 — warm gold (light → dark text)
            onSwatch: false
        )
    ]

    var body: some View {
        ZStack {
            // Animated swatch background — transitions with page
            pages[currentPage].swatchColor
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: currentPage)

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        pageView(page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Page indicator + CTA — cream panel at bottom
                VStack(spacing: XBillSpacing.xl) {
                    HStack(spacing: XBillSpacing.sm) {
                        ForEach(0..<pages.count, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPage
                                      ? (pages[currentPage].onSwatch ? Color.white : Color.clayUbe)
                                      : Color.white.opacity(0.35))
                                .frame(width: i == currentPage ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }

                    if currentPage < pages.count - 1 {
                        HStack {
                            Button("Skip") { onComplete() }
                                .font(.xbillButtonMedium)
                                .foregroundStyle(pages[currentPage].onSwatch
                                                 ? Color.white.opacity(0.7)
                                                 : Color.clayCharcoal)

                            Spacer()

                            Button {
                                withAnimation { currentPage += 1 }
                            } label: {
                                Text("Next")
                                    .font(.xbillButtonLarge)
                                    .foregroundStyle(pages[currentPage].onSwatch
                                                     ? pages[currentPage].swatchColor
                                                     : Color.white)
                                    .frame(width: 120, height: 48)
                                    .background(pages[currentPage].onSwatch
                                                ? Color.white
                                                : Color.clayUbe)
                                    .clipShape(RoundedRectangle(cornerRadius: XBillRadius.md))
                            }
                            .buttonStyle(ClayButtonStyle())
                        }
                        .padding(.horizontal, XBillSpacing.xl)
                    } else {
                        VStack(spacing: XBillSpacing.md) {
                            Button {
                                onComplete()
                            } label: {
                                Text("Get Started")
                                    .font(.xbillButtonLarge)
                                    .foregroundStyle(Color.white)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(Color.clayUbe)
                                    .clipShape(RoundedRectangle(cornerRadius: XBillRadius.md))
                            }
                            .buttonStyle(ClayButtonStyle())
                            .padding(.horizontal, XBillSpacing.xl)

                            if let trySample = onTrySampleData {
                                Button {
                                    isCreatingSample = true
                                    Task {
                                        await trySample()
                                        isCreatingSample = false
                                        onComplete()
                                    }
                                } label: {
                                    if isCreatingSample {
                                        ProgressView()
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                    } else {
                                        Text("Try with sample data")
                                            .font(.xbillButtonMedium)
                                            .foregroundStyle(Color.clayUbe)
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                    }
                                }
                                .disabled(isCreatingSample)
                                .padding(.horizontal, XBillSpacing.xl)
                            }
                        }
                    }
                }
                .padding(.bottom, XBillSpacing.xxxl)
                .padding(.top, XBillSpacing.lg)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: XBillSpacing.xl) {
            Spacer()

            Image(systemName: page.icon)
                .font(.system(size: 80))
                .foregroundStyle(page.onSwatch ? Color.white : Color.clayUbe)
                .accessibilityHidden(true)

            VStack(spacing: XBillSpacing.md) {
                Text(page.title)
                    .font(.xbillLargeTitle)
                    .foregroundStyle(page.onSwatch ? Color.white : Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text(page.description)
                    .font(.xbillBodyMedium)
                    .foregroundStyle(page.onSwatch ? Color.white.opacity(0.8) : Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, XBillSpacing.xl)
            }

            Spacer()
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - OnboardingPage

private struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let swatchColor: Color
    let onSwatch: Bool   // true = dark swatch (white text); false = light swatch (dark text)
}

#Preview {
    OnboardingView(onComplete: {})
}

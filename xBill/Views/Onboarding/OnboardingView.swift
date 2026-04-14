import SwiftUI

// MARK: - OnboardingView
// Shown once after first sign-in. Dismissed by tapping "Get Started".
// Completion is persisted via @AppStorage so it only shows once per install.

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "dollarsign.circle.fill",
            title: "Welcome to xBill",
            description: "The easiest way to split expenses with friends, roommates, and travel buddies — no awkward money talks required."
        ),
        OnboardingPage(
            icon: "person.3.fill",
            title: "Create Groups",
            description: "Organise expenses by trip, household, or occasion. Everyone in the group can add expenses and see what they owe at a glance."
        ),
        OnboardingPage(
            icon: "camera.viewfinder",
            title: "Scan Receipts",
            description: "Point your camera at any receipt. xBill reads the items, splits the total, and assigns shares automatically using on-device AI."
        ),
        OnboardingPage(
            icon: "chart.bar.fill",
            title: "Stay Balanced",
            description: "See live balances across all your groups. Settle up with one tap and track your spending history over time."
        )
    ]

    var body: some View {
        ZStack {
            Color.bgSecondary.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        pageView(page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Page indicator + CTA
                VStack(spacing: XBillSpacing.xl) {
                    HStack(spacing: XBillSpacing.sm) {
                        ForEach(0..<pages.count, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPage ? Color.brandPrimary : Color.separator)
                                .frame(width: i == currentPage ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }

                    if currentPage < pages.count - 1 {
                        HStack {
                            Button("Skip") {
                                onComplete()
                            }
                            .font(.xbillButtonMedium)
                            .foregroundStyle(Color.textTertiary)

                            Spacer()

                            XBillButton(title: "Next", style: .primary) {
                                withAnimation { currentPage += 1 }
                            }
                            .frame(width: 120)
                        }
                        .padding(.horizontal, XBillSpacing.xl)
                    } else {
                        XBillButton(title: "Get Started", style: .primary) {
                            onComplete()
                        }
                        .padding(.horizontal, XBillSpacing.xl)
                    }
                }
                .padding(.bottom, XBillSpacing.xxxl)
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
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)

            VStack(spacing: XBillSpacing.md) {
                Text(page.title)
                    .font(.xbillLargeTitle)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text(page.description)
                    .font(.xbillBodyMedium)
                    .foregroundStyle(Color.textSecondary)
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
}

#Preview {
    OnboardingView(onComplete: {})
}

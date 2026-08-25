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
    /// See `launchPlaceholder` — bounds how long the launch screen may be shown.
    @State private var launchWaitElapsed = false
    @State private var sampleDataError: AppError?
    // Owned here so onTrySampleData can write into the same instance that MainTabView reads.
    @State private var homeVM = HomeViewModel()
    #if DEBUG
    @State private var uitestRoute = UITestLaunchRoute.current
    #endif

    var body: some View {
        ZStack {
            XBillTheme.background.ignoresSafeArea()

            #if DEBUG
            if let uitestRoute, uitestRoute.isAuthIndependent {
                uitestRouteView(for: uitestRoute)
            } else {
                mainContent
            }
            #else
            mainContent
            #endif
        }
        .animation(.easeInOut(duration: 0.4), value: authVM.isInPasswordRecovery)
        .animation(.easeInOut(duration: 0.4), value: authVM.currentUser != nil)
        .animation(.easeInOut(duration: 0.4), value: hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.3), value: lockService.isLocked)
        .onChange(of: scenePhase) { oldPhase, phase in
            AppDiagnostics.log(.lifecycle, "ContentView.scenePhase", [
                ("from", String(describing: oldPhase)),
                ("to", String(describing: phase)),
                ("appLockEnabled", lockService.isEnabled),
                ("isLocked", lockService.isLocked)
            ])
            if phase == .background {
                lockService.lock()
            }
        }
        .alert(sampleDataError?.errorDescription ?? "Sample Data Error", isPresented: Binding(
            get: { sampleDataError != nil },
            set: { if !$0 { sampleDataError = nil } }
        )) {
            Button("OK") { sampleDataError = nil }
        } message: {
            Text(sampleDataError?.errorDescription ?? "Could not create sample data.")
        }
        #if DEBUG
        .task {
            await refreshUITestRouteDuringLaunch()
        }
        #endif
    }

    @ViewBuilder
    private var mainContent: some View {
        if authVM.isInPasswordRecovery {
            ResetPasswordView(authVM: authVM)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if authVM.currentUser != nil {
            if hasCompletedOnboarding {
                #if DEBUG
                if let uitestRoute {
                    uitestRouteView(for: uitestRoute)
                } else {
                    mainTabContent
                }
                #else
                mainTabContent
                #endif
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
        } else if !authVM.hasResolvedInitialSession && !launchWaitElapsed {
            // The SDK has not yet said whether a stored session exists. `currentUser` is nil during
            // that window on **every** cold launch, so showing `AuthView` here is what produced
            // "it opens on the login screen and then logs itself in".
            //
            // This is the app's own launch screen continued, not a spinner: matching
            // `UILaunchScreen` means the hand-off from the system launch image is invisible, so a
            // returning user sees one continuous screen rather than a flash of the wrong one.
            launchPlaceholder
        } else {
            AuthView(vm: authVM)
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
        }
    }

    /// Deliberately silent — no spinner and no copy. Session restore is normally imperceptible;
    /// announcing it would draw attention to a wait that usually is not one.
    private var launchPlaceholder: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            XBillWordmark()
        }
        .transition(.opacity)
        .accessibilityIdentifier("xBill.launch.placeholder")
        .task {
            // Safety net. If the auth stream never yields `.initialSession` — a version change, a
            // Keychain the SDK cannot read, an error path nobody predicted — this screen would
            // otherwise be terminal, and a blank wordmark forever is far worse than the flash it
            // replaced. After this the app falls through to `AuthView`, i.e. the pre-fix behaviour.
            try? await Task.sleep(for: .seconds(3))
            launchWaitElapsed = true
        }
    }

    private var mainTabContent: some View {
        MainTabView(authVM: authVM, homeVM: homeVM)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal:   .move(edge: .trailing).combined(with: .opacity)
            ))
    }

    #if DEBUG
    private func refreshUITestRouteDuringLaunch() async {
        for _ in 0..<20 {
            let route = UITestLaunchRoute.current
            if route != uitestRoute {
                uitestRoute = route
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    @ViewBuilder
    private func uitestRouteView(for route: UITestLaunchRoute) -> some View {
        switch route {
        case .groups:
            GroupListView(vm: homeVM)
                .task {
                    await homeVM.loadCurrentUser()
                    await homeVM.loadAll()
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .trailing).combined(with: .opacity)
                ))
        case .createGroup:
            UITestCreateGroupRootView(vm: homeVM)
                .task {
                    await homeVM.loadCurrentUser()
                    await homeVM.loadAll()
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .trailing).combined(with: .opacity)
                ))
        case .createGroupThenOpen:
            UITestCreateGroupRootView(vm: homeVM, opensCreatedGroupAfterCreate: true)
                .task {
                    await homeVM.loadCurrentUser()
                    await homeVM.loadAll()
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .trailing).combined(with: .opacity)
                ))
        case .firstGroupDetail:
            GroupListView(vm: homeVM)
                .task {
                    await homeVM.loadCurrentUser()
                    await homeVM.loadAll()
                    if let firstGroup = homeVM.groups.first {
                        homeVM.groupsNavigationPath = NavigationPath()
                        homeVM.groupsNavigationPath.append(firstGroup)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .trailing).combined(with: .opacity)
                ))
        }
    }
    #endif
}

#if DEBUG
private enum UITestLaunchRoute: Equatable {
    case groups
    case createGroup
    case createGroupThenOpen
    case firstGroupDetail

    static var current: UITestLaunchRoute? {
        let process = ProcessInfo.processInfo
        guard process.arguments.contains("--uitesting")
            || process.environment["XBILL_UITESTING"] == "1" else {
            return nil
        }

        let routeName = process.value(forArgument: "--uitest-route")
            ?? process.environment["XBILL_UITEST_ROUTE"]
            ?? UserDefaults.standard.string(forKey: "XBILL_UITEST_ROUTE")

        switch routeName {
        case "groups":
            return .groups
        case "createGroup":
            return .createGroup
        case "createGroupThenOpen":
            return .createGroupThenOpen
        case "firstGroupDetail":
            return .firstGroupDetail
        default:
            return .groups
        }
    }

    var isAuthIndependent: Bool {
        switch self {
        case .createGroup:
            return true
        case .groups, .createGroupThenOpen, .firstGroupDetail:
            return false
        }
    }
}

private extension ProcessInfo {
    func value(forArgument name: String) -> String? {
        guard let index = arguments.firstIndex(of: name),
              arguments.indices.contains(arguments.index(after: index)) else {
            return nil
        }
        return arguments[arguments.index(after: index)]
    }
}

private struct UITestCreateGroupRootView: View {
    @Bindable var vm: HomeViewModel
    var opensCreatedGroupAfterCreate = false
    @State private var showsCreateGroup = true

    var body: some View {
        if showsCreateGroup {
            CreateGroupView(
                onCreated: { group in
                    vm.groups.append(group)
                    SpotlightService.indexGroups(vm.groups)
                    showsCreateGroup = false
                    if opensCreatedGroupAfterCreate {
                        vm.groupsNavigationPath = NavigationPath()
                        vm.groupsNavigationPath.append(group)
                    }
                },
                inviterName: vm.currentUser?.displayName ?? "Someone",
                onCancel: { showsCreateGroup = false }
            )
        } else {
            GroupListView(vm: vm)
        }
    }
}
#endif

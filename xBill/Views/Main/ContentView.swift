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
    #if DEBUG
    @State private var uitestRoute = UITestLaunchRoute.current
    #endif

    var body: some View {
        ZStack {
            XBillTheme.background.ignoresSafeArea()

            if authVM.isInPasswordRecovery {
                ResetPasswordView(authVM: authVM)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if authVM.currentUser != nil {
                if hasCompletedOnboarding {
                    #if DEBUG
                    if let uitestRoute {
                        switch uitestRoute {
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
                    } else {
                        MainTabView(authVM: authVM, homeVM: homeVM)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal:   .move(edge: .trailing).combined(with: .opacity)
                            ))
                    }
                    #else
                    MainTabView(authVM: authVM, homeVM: homeVM)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal:   .move(edge: .trailing).combined(with: .opacity)
                        ))
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

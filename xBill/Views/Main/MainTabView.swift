//
//  MainTabView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI
import UIKit

struct MainTabView: View {
    @Bindable var authVM: AuthViewModel
    @Environment(AppState.self) private var appState
    @State private var homeVM = HomeViewModel()
    @State private var activityVM = ActivityViewModel()
    @State private var profileVM = ProfileViewModel()
    @State private var selectedTab: Tab = .home
    @State private var showQuickAddExpense = false
    @State private var quickActionScan = false

    enum Tab: Hashable {
        case home, groups, friends, activity, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(vm: homeVM)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)

            GroupListView(vm: homeVM)
                .tabItem { Label("Groups", systemImage: "person.3.fill") }
                .tag(Tab.groups)

            FriendsView(currentUserID: homeVM.currentUser?.id ?? UUID())
                .tabItem { Label("Friends", systemImage: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90") }
                .tag(Tab.friends)

            ActivityView(vm: activityVM)
                .tabItem { Label("Activity", systemImage: "bell.fill") }
                .badge(activityVM.unreadCount > 0 ? activityVM.unreadCount : 0)
                .tag(Tab.activity)

            ProfileView(vm: profileVM, onSignOut: {
                Task { await authVM.signOut() }
            })
            .tabItem { Label("Profile", systemImage: "person.fill") }
            .tag(Tab.profile)
        }
        .tint(Color.brandPrimary)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
        .sheet(item: $authVM.pendingJoinRequest) { request in
            JoinGroupView(token: request.token) {
                await homeVM.loadAll()
            }
        }
        .sheet(isPresented: $showQuickAddExpense) {
            QuickAddExpenseSheet(
                groups: homeVM.groups,
                currentUserID: homeVM.currentUser?.id ?? UUID(),
                startWithScan: quickActionScan,
                onSaved: { await homeVM.loadAll() }
            )
        }
        .task {
            await homeVM.loadCurrentUser()
            await homeVM.loadAll()
            await profileVM.load()
            let granted = (try? await NotificationService.shared.requestAuthorization()) ?? false
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        // Handle quick actions (warm start and cold start after load)
        .task(id: appState.pendingQuickAction) {
            guard let action = appState.pendingQuickAction else { return }
            if homeVM.groups.isEmpty { await homeVM.loadAll() }
            switch action {
            case .addExpense:
                quickActionScan = false
                selectedTab = .groups
                showQuickAddExpense = true
            case .scanReceipt:
                quickActionScan = true
                selectedTab = .groups
                showQuickAddExpense = true
            }
            appState.pendingQuickAction = nil
        }
        // Handle Spotlight navigation
        .task(id: appState.spotlightTarget) {
            guard let target = appState.spotlightTarget else { return }
            if homeVM.groups.isEmpty { await homeVM.loadAll() }
            switch target {
            case .group(let id):
                if let group = homeVM.groups.first(where: { $0.id == id }) {
                    selectedTab = .groups
                    homeVM.groupsNavigationPath = NavigationPath()
                    homeVM.groupsNavigationPath.append(group)
                }
            }
            appState.spotlightTarget = nil
        }
    }
}

#Preview {
    MainTabView(authVM: AuthViewModel())
}

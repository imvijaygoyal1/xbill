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
    @State private var showNotificationPrompt = false
    @State private var addFriendPreloadedUser: User? = nil
    @State private var showAddFriendFromQR = false
    @AppStorage("hasPromptedNotificationPermission") private var hasPromptedNotification = false

    enum Tab: Hashable {
        case home, groups, friends, activity, profile
    }

    private var tabItems: [(Tab, String, String)] {
        [
            (.home, "Home", "house.fill"),
            (.groups, "Groups", "person.3.fill"),
            (.friends, "Friends", "person.2.fill"),
            (.activity, "Alerts", "bell.fill"),
            (.profile, "Profile", "person.fill")
        ]
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(vm: homeVM)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)

            GroupListView(vm: homeVM)
                .tabItem { Label("Groups", systemImage: "person.3.fill") }
                .tag(Tab.groups)

            FriendsView(currentUserID: homeVM.currentUser?.id ?? UUID(), allGroups: homeVM.groups)
                .tabItem { Label("Friends", systemImage: "person.2.fill") }
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
        .tint(AppColors.primary)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            XBillTabBar(
                tabs: tabItems,
                selection: $selectedTab,
                badgeCounts: [.activity: activityVM.unreadCount]
            )
        }
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
            let status = await NotificationService.shared.authorizationStatus()
            if status == .authorized || status == .provisional {
                UIApplication.shared.registerForRemoteNotifications()
            } else if status == .notDetermined && !hasPromptedNotification {
                showNotificationPrompt = true
            }
        }
        .sheet(isPresented: $showNotificationPrompt) {
            NotificationPermissionView {
                hasPromptedNotification = true
                showNotificationPrompt  = false
                let granted = (try? await NotificationService.shared.requestAuthorization()) ?? false
                if granted { UIApplication.shared.registerForRemoteNotifications() }
            } onSkip: {
                hasPromptedNotification = true
                showNotificationPrompt  = false
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
        // Handle push notification tap → navigate to group
        .task(id: appState.pendingNotificationTarget) {
            guard let target = appState.pendingNotificationTarget else { return }
            if homeVM.groups.isEmpty { await homeVM.loadAll() }
            switch target {
            case .group(let id):
                if let group = homeVM.groups.first(where: { $0.id == id }) {
                    selectedTab = .groups
                    homeVM.groupsNavigationPath = NavigationPath()
                    homeVM.groupsNavigationPath.append(group)
                }
            }
            appState.pendingNotificationTarget = nil
        }
        // Handle xbill://add/<userID> deep link → open AddFriendView pre-loaded
        .task(id: appState.pendingAddFriendUserID) {
            guard let userID = appState.pendingAddFriendUserID else { return }
            if let profile = try? await FriendService.shared.searchProfiles(query: userID.uuidString).first {
                addFriendPreloadedUser = profile
            }
            selectedTab = .friends
            showAddFriendFromQR = true
            appState.pendingAddFriendUserID = nil
        }
        .sheet(isPresented: $showAddFriendFromQR) {
            if let user = homeVM.currentUser {
                AddFriendView(
                    currentUserID: user.id,
                    preloadedUser: addFriendPreloadedUser
                ) { }
            }
        }
    }
}

#Preview {
    MainTabView(authVM: AuthViewModel())
}

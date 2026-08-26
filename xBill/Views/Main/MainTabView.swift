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
    var homeVM: HomeViewModel   // owned by ContentView; passed in so onTrySampleData writes to the same instance
    @Environment(AppState.self) private var appState
    @State private var activityVM = ActivityViewModel()
    @State private var profileVM = ProfileViewModel()
    @State private var selectedTab: Tab
    @State private var showQuickAddExpense = false
    @State private var quickActionScan = false
    @State private var lockService = AppLockService.shared
    @State private var showNotificationPrompt = false
    @State private var addFriendPreloadedUser: User? = nil
    @State private var showAddFriendFromQR = false
    @AppStorage("hasPromptedNotificationPermission") private var hasPromptedNotification = false

    enum Tab: Hashable {
        case home, groups, friends, activity, profile
    }

    init(authVM: AuthViewModel, homeVM: HomeViewModel) {
        self.authVM = authVM
        self.homeVM = homeVM
        _selectedTab = State(initialValue: Self.initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(vm: homeVM)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                        .accessibilityIdentifier("xBill.tab.home")
                }
                .tag(Tab.home)

            GroupListView(vm: homeVM)
                .tabItem {
                    Label("Groups", systemImage: "person.3.fill")
                        .accessibilityIdentifier("xBill.tab.groups")
                }
                .tag(Tab.groups)

            // Only pass a real userID — UUID() causes IOU ownership direction to be
            // wrong for the whole session if this renders before loadCurrentUser() completes.
            FriendsView(currentUserID: homeVM.currentUser?.id, allGroups: homeVM.groups)
                .tabItem {
                    Label("Friends", systemImage: "person.2.fill")
                        .accessibilityIdentifier("xBill.tab.friends")
                }
                .tag(Tab.friends)

            ActivityView(vm: activityVM)
                .tabItem {
                    Label("Recent", systemImage: "bell.fill")
                        .accessibilityIdentifier("xBill.tab.activity")
                }
                .badge(activityVM.unreadCount)
                .tag(Tab.activity)

            ProfileView(vm: profileVM, onSignOut: {
                Task { await authVM.signOut() }
            })
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle.fill")
                    .accessibilityIdentifier("xBill.tab.profile")
            }
            .tag(Tab.profile)
        }
        .tint(AppColors.primary)
        .sheet(item: $authVM.pendingJoinRequest) { request in
            JoinGroupView(token: request.token) {
                await homeVM.loadAll()
            }
        }
        .sheet(isPresented: $showQuickAddExpense) {
            if let userID = homeVM.currentUser?.id {
                QuickAddExpenseSheet(
                    groups: homeVM.groups,
                    currentUserID: userID,
                    startWithScan: quickActionScan,
                    onSaved: { await homeVM.loadAll() }
                )
            }
        }
        .task {
            await homeVM.loadCurrentUser()
            await homeVM.loadAll()
            await activityVM.load()
            let status = await NotificationService.shared.authorizationStatus()
            if status.allowsPushRegistration {
                UIApplication.shared.registerForRemoteNotifications()
            } else if status == .denied {
                await AuthService.shared.deleteDeviceTokensReportingFailure()
            } else if status == .notDetermined && !hasPromptedNotification {
                showNotificationPrompt = true
            }
        }
        .sheet(isPresented: $showNotificationPrompt) {
            NotificationPermissionView {
                hasPromptedNotification = true
                showNotificationPrompt  = false
                let granted = (try? await NotificationService.shared.requestAuthorization()) ?? false
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    await AuthService.shared.deleteDeviceTokensReportingFailure()
                }
            } onSkip: {
                hasPromptedNotification = true
                showNotificationPrompt  = false
            }
        }
        // Handle quick actions (warm start and cold start after load)
        .task(id: appState.pendingQuickAction) {
            guard let action = appState.pendingQuickAction else { return }
            if homeVM.currentUser == nil { await homeVM.loadCurrentUser() }
            if homeVM.groups.isEmpty { await homeVM.loadAll() }
            // Do not open the sheet without a real user — UUID() fallback creates orphaned DB records.
            guard homeVM.currentUser != nil else {
                appState.pendingQuickAction = nil
                return
            }
            switch action {
            case .addExpense:
                quickActionScan = false
                selectedTab = .groups
                if homeVM.currentUser != nil && !homeVM.groups.isEmpty {
                    showQuickAddExpense = true
                }
            case .scanReceipt:
                quickActionScan = true
                selectedTab = .groups
                if homeVM.currentUser != nil && !homeVM.groups.isEmpty {
                    showQuickAddExpense = true
                }
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
            case .activity:
                selectedTab = .activity
            }
            appState.pendingNotificationTarget = nil
        }
        // Handle xbill://add/<userID> deep link → open AddFriendView pre-loaded
        .task(id: appState.pendingAddFriendUserID) {
            guard let userID = appState.pendingAddFriendUserID else { return }

            // INV-08. This used to CLEAR the pending id when `currentUser` was nil and return —
            // discarding the invite outright. On a cold launch from a link that is the normal
            // state: the deep link is parsed immediately, while the session restore is still in
            // flight (the same window as LAUNCH-01). The app opened and nothing happened, and the
            // request was gone before the user finished loading.
            //
            // The sibling `pendingQuickAction` handler above already does the right thing —
            // **load the user, then guard** — and this now matches it. The original comment said
            // the clear existed "to avoid a transparent flash": a cosmetic concern that was
            // silently throwing away the thing the user tapped.
            if homeVM.currentUser == nil { await homeVM.loadCurrentUser() }
            guard homeVM.currentUser != nil else {
                // Still no user after an explicit load — genuinely signed out. Leave the pending id
                // in place so signing in and returning still honours the link.
                return
            }
            // INV-09: through the SECURITY DEFINER preview, not a direct select on `profiles`.
            // That table's SELECT policy requires a shared active group, which a NEW friend never
            // has — so the direct lookup returned nothing and this screen opened with nobody on it.
            addFriendPreloadedUser = try? await FriendService.shared.fetchAddFriendPreview(userID: userID)
            selectedTab = .friends
            showAddFriendFromQR = true
            appState.pendingAddFriendUserID = nil
        }
        .sheet(isPresented: $showAddFriendFromQR) {
            // currentUser is guaranteed non-nil: the task handler guards on it before setting showAddFriendFromQR.
            if let user = homeVM.currentUser {
                AddFriendView(
                    currentUserID: user.id,
                    preloadedUser: addFriendPreloadedUser
                ) { }
            }
        }
        .onChange(of: authVM.currentUser) { _, newUser in
            // Keep homeVM.currentUser in sync so profile-name changes propagate
            // without waiting for homeVM.loadCurrentUser() to run again.
            homeVM.currentUser = newUser
            // Seed the profile VM so the profile card shows user data immediately
            // when the Profile tab is opened, without a redundant auth.session call.
            profileVM.user = newUser
            if !profileVM.isEditing, let name = newUser?.displayName {
                profileVM.displayName = name
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            AppDiagnostics.log(.lifecycle, "MainTabView.didBecomeActive", [
                ("connected", NetworkMonitor.shared.isConnected),
                ("groups", homeVM.groups.count),
                ("isLocked", lockService.isLocked)
            ])
            // Do not refresh activity behind the lock screen. Face ID unlock
            // must finish first, otherwise a stale server response can replace
            // a local read/unread change during the transition.
            guard !lockService.isLocked else { return }
            Task {
                await activityVM.load()
                await homeVM.loadAll()
                AppDiagnostics.log(.lifecycle, "MainTabView.didBecomeActive.refreshComplete")
            }
        }
        .onChange(of: lockService.isLocked) { _, isLocked in
            guard !isLocked else { return }
            AppDiagnostics.log(.lifecycle, "MainTabView.unlocked.refreshBegin")
            Task {
                await activityVM.load()
                AppDiagnostics.log(.lifecycle, "MainTabView.unlocked.refreshComplete")
            }
        }
    }

    private static var initialTab: Tab {
        #if UI_TESTING
        let process = ProcessInfo.processInfo
        // A test that must reach a specific tab should land on it, not walk the tab bar. Chained
        // `tapTab` navigation is where the UI-01 sweep kept breaking — and a probe that cannot
        // reach its screen reports nothing rather than failing.
        let requested = process.environment["XBILL_INITIAL_TAB"]
            ?? UserDefaults.standard.string(forKey: "XBILL_INITIAL_TAB")
        if process.arguments.contains("--initial-tab-groups") { return .groups }
        switch requested {
        case "groups":   return .groups
        case "friends":  return .friends
        case "activity": return .activity
        case "profile":  return .profile
        default:         return .home
        }
        #else
        return .home
        #endif
    }

}

#Preview {
    MainTabView(authVM: AuthViewModel(), homeVM: HomeViewModel())
}

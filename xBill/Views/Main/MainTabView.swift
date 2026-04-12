import SwiftUI
import UIKit

struct MainTabView: View {
    @Bindable var authVM: AuthViewModel
    @State private var homeVM = HomeViewModel()
    @State private var activityVM = ActivityViewModel()
    @State private var profileVM = ProfileViewModel()
    @State private var selectedTab: Tab = .home

    enum Tab: Hashable {
        case home, groups, activity, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(vm: homeVM)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)

            GroupListView(vm: homeVM)
                .tabItem { Label("Groups", systemImage: "person.3.fill") }
                .tag(Tab.groups)

            ActivityView(vm: activityVM)
                .tabItem { Label("Activity", systemImage: "bolt.fill") }
                .tag(Tab.activity)

            ProfileView(vm: profileVM, onSignOut: {
                Task { await authVM.signOut() }
            })
            .tabItem { Label("Profile", systemImage: "person.fill") }
            .tag(Tab.profile)
        }
        .tint(Color.brandPrimary)
        .toolbarBackground(Color.tabBarBg, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(item: $authVM.pendingJoinRequest) { request in
            JoinGroupView(token: request.token) {
                await homeVM.loadAll()
            }
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
    }
}

#Preview {
    MainTabView(authVM: AuthViewModel())
}

//
//  GroupListView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct GroupListView: View {
    @Bindable var vm: HomeViewModel
    @State private var showCreateGroup = false
    @State private var showArchived = false
    @State private var searchText = ""

    private var filteredGroups: [BillGroup] {
        filter(vm.groups)
    }

    private var filteredArchivedGroups: [BillGroup] {
        filter(vm.archivedGroups)
    }

    private func filter(_ groups: [BillGroup]) -> [BillGroup] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return groups }
        return groups.filter {
            $0.name.lowercased().contains(q) ||
            $0.currency.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack(path: $vm.groupsNavigationPath) {
            Group {
                if vm.isLoading && vm.groups.isEmpty && vm.archivedGroups.isEmpty {
                    LoadingOverlay(message: "Loading groups…")
                } else if vm.groups.isEmpty && vm.archivedGroups.isEmpty {
                    EmptyStateView(
                        icon: "person.3.fill",
                        title: "No Groups Yet",
                        message: "Create a group to start splitting expenses with friends.",
                        actionLabel: "Create Group",
                        action: { showCreateGroup = true }
                    )
                } else {
                    groupList
                }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search groups")
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreateGroup = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView { newGroup in
                    vm.groups.append(newGroup)
                    SpotlightService.indexGroups(vm.groups)
                }
            }
            .refreshable {
                await vm.refresh()
                await vm.loadArchivedGroups()
            }
            .task { await vm.loadArchivedGroups() }
        }
        .errorAlert(item: $vm.errorAlert)
    }

    private var groupList: some View {
        List {
            // Active groups
            if !filteredGroups.isEmpty {
                Section {
                    ForEach(filteredGroups) { group in
                        NavigationLink(value: group) {
                            groupRow(group, isArchived: false)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            let group = filteredGroups[i]
                            Task { await vm.deleteGroup(group) }
                        }
                    }
                }
            }

            // Archived groups — collapsible section
            if !filteredArchivedGroups.isEmpty {
                Section {
                    if showArchived {
                        ForEach(filteredArchivedGroups) { group in
                            NavigationLink(value: group) {
                                groupRow(group, isArchived: true)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .leading) {
                                Button {
                                    Task { await vm.unarchiveGroup(group) }
                                } label: {
                                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                                }
                                .tint(Color.brandPrimary)
                            }
                        }
                    }
                } header: {
                    HStack {
                            Text("ARCHIVED (\(filteredArchivedGroups.count))")
                            .font(.appCaptionMedium)
                            .tracking(1.08)
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        Image(systemName: showArchived ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { showArchived.toggle() }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .listRowSeparatorTint(AppColors.border)
        .navigationDestination(for: BillGroup.self) { group in
            if let userID = vm.currentUser?.id {
                GroupDetailView(
                    vm: GroupViewModel(group: group),
                    currentUserID: userID,
                    onGroupStatusChanged: {
                        await vm.refresh()
                        await vm.loadArchivedGroups()
                    }
                )
            }
        }
    }

    private func groupRow(_ group: BillGroup, isArchived: Bool) -> some View {
        XBillGroupCard(
            group: group,
            subtitle: "\(group.currency) · \(group.createdAt.shortFormatted)",
            trailing: isArchived ? "Archived" : nil
        )
        .opacity(isArchived ? 0.72 : 1)
    }
}

#Preview {
    GroupListView(vm: HomeViewModel())
}

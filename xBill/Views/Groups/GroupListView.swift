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
                    XBillScreenContainer(contentSpacing: AppSpacing.xl) {
                        groupsHeader
                        EmptyStateView(
                            icon: "person.3.fill",
                            title: "No Groups Yet",
                            message: "Create a group to start splitting expenses with friends.",
                            actionLabel: "Create Group",
                            action: { showCreateGroup = true },
                            illustration: .groups
                        )
                    }
                } else {
                    groupList
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView(
                    onCreated: { newGroup in
                        vm.groups.append(newGroup)
                        SpotlightService.indexGroups(vm.groups)
                    },
                    inviterName: vm.currentUser?.displayName ?? "Someone"
                )
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
        XBillScrollView(spacing: AppSpacing.xl) {
            groupsHeader
            XBillSearchBar(placeholder: "Search groups", text: $searchText)

            if !searchText.isEmpty && filteredGroups.isEmpty && filteredArchivedGroups.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No groups match \"\(searchText)\"")
                )
            }

            if !filteredGroups.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    XBillSectionHeader("Active Groups", subtitle: groupCountText(filteredGroups.count))
                    ForEach(filteredGroups) { group in
                        NavigationLink(value: group) { groupRow(group, isArchived: false) }
                            .buttonStyle(.plain)
                    }
                }
            }

            if !filteredArchivedGroups.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Button {
                        withAnimation { showArchived.toggle() }
                    } label: {
                        XBillArchivedRow(
                            icon: "archivebox.fill",
                            title: "Archived",
                            subtitle: groupCountText(filteredArchivedGroups.count),
                            isExpanded: showArchived
                        )
                    }
                    .buttonStyle(.plain)

                    if showArchived {
                        ForEach(filteredArchivedGroups) { group in
                            NavigationLink(value: group) { groupRow(group, isArchived: true) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        Task { await vm.unarchiveGroup(group) }
                                    } label: {
                                        Label("Unarchive", systemImage: "tray.and.arrow.up")
                                    }
                                }
                        }
                    }
                }
            }
        }
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

    private var groupsHeader: some View {
        XBillPageHeader(title: "Groups") {
            XBillCircularIconButton(
                systemImage: "plus",
                accessibilityLabel: "Create Group"
            ) {
                showCreateGroup = true
            }
            .accessibilityIdentifier("xBill.groups.createButton")
        }
        .padding(.horizontal, -AppSpacing.lg)
    }

    private func groupRow(_ group: BillGroup, isArchived: Bool) -> some View {
        XBillGroupCard(
            group: group,
            subtitle: "\(group.currency) · \(group.createdAt.shortFormatted)",
            trailing: isArchived ? "Archived" : nil,
            showsChevron: true
        )
        .opacity(isArchived ? 0.72 : 1)
    }

    private func groupCountText(_ count: Int) -> String {
        "\(count) group\(count == 1 ? "" : "s")"
    }
}

#Preview("Groups") {
    GroupListView(vm: HomeViewModel())
}

#Preview("Groups Dark") {
    GroupListView(vm: HomeViewModel())
        .preferredColorScheme(.dark)
}

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
                    XBillScreenContainer {
                        XBillPageHeader(title: "Groups")
                            .padding(.horizontal, -AppSpacing.lg)
                        XBillSearchBar(placeholder: "Search groups", text: $searchText)
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
        XBillScrollView {
            XBillPageHeader(title: "Groups") {
                Button { showCreateGroup = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppColors.primary)
                        .frame(width: AppSpacing.tapTarget, height: AppSpacing.tapTarget)
                }
                .accessibilityLabel("Create Group")
            }
            .padding(.horizontal, -AppSpacing.lg)

            XBillSearchBar(placeholder: "Search groups", text: $searchText)

            if !filteredGroups.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    sectionTitle("ACTIVE GROUPS")
                    ForEach(filteredGroups) { group in
                        NavigationLink(value: group) { groupRow(group, isArchived: false) }
                            .buttonStyle(.plain)
                    }
                }
            }

            if !filteredArchivedGroups.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Button {
                        withAnimation { showArchived.toggle() }
                    } label: {
                        HStack {
                            sectionTitle("ARCHIVED (\(filteredArchivedGroups.count))")
                            Spacer()
                            Image(systemName: showArchived ? "chevron.up" : "chevron.down")
                                .font(.appCaptionMedium)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .frame(minHeight: AppSpacing.tapTarget)
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

    private func groupRow(_ group: BillGroup, isArchived: Bool) -> some View {
        XBillGroupCard(
            group: group,
            subtitle: "\(group.currency) · \(group.createdAt.shortFormatted)",
            trailing: isArchived ? "Archived" : nil
        )
        .opacity(isArchived ? 0.72 : 1)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.appCaptionMedium)
            .tracking(1.08)
            .foregroundStyle(AppColors.textSecondary)
    }
}

#Preview {
    GroupListView(vm: HomeViewModel())
}

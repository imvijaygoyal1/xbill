import SwiftUI

struct GroupListView: View {
    @Bindable var vm: HomeViewModel
    @State private var showCreateGroup = false
    @State private var showArchived = false

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
            .toolbarBackground(Color.navBarBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreateGroup = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView { _ in await vm.refresh() }
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
            if !vm.groups.isEmpty {
                Section {
                    ForEach(vm.groups) { group in
                        NavigationLink(value: group) {
                            groupRow(group, isArchived: false)
                        }
                        .listRowBackground(Color.bgCard)
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            let group = vm.groups[i]
                            Task { await vm.deleteGroup(group) }
                        }
                    }
                }
            }

            // Archived groups — collapsible section
            if !vm.archivedGroups.isEmpty {
                Section {
                    if showArchived {
                        ForEach(vm.archivedGroups) { group in
                            NavigationLink(value: group) {
                                groupRow(group, isArchived: true)
                            }
                            .listRowBackground(Color.bgCard)
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
                        Text("ARCHIVED (\(vm.archivedGroups.count))")
                            .font(.xbillUpperLabel)
                            .tracking(1.08)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Image(systemName: showArchived ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { showArchived.toggle() }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.bgSecondary)
        .listRowSeparatorTint(Color.separator)
        .navigationDestination(for: BillGroup.self) { group in
            GroupDetailView(
                vm: GroupViewModel(group: group),
                currentUserID: vm.currentUser?.id ?? UUID()
            )
        }
    }

    private func groupRow(_ group: BillGroup, isArchived: Bool) -> some View {
        HStack(spacing: XBillSpacing.md) {
            Text(group.emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.brandSurface)
                .clipShape(Circle())
                .opacity(isArchived ? 0.6 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.xbillBodyLarge)
                    .foregroundStyle(isArchived ? Color.textSecondary : Color.textPrimary)
                Text("\(group.currency) · \(group.createdAt.shortFormatted)")
                    .font(.xbillBodySmall)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            if isArchived {
                Image(systemName: "archivebox")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, XBillSpacing.xs)
    }
}

#Preview {
    GroupListView(vm: HomeViewModel())
}

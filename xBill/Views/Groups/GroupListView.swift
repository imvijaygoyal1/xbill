import SwiftUI

struct GroupListView: View {
    @Bindable var vm: HomeViewModel
    @State private var showCreateGroup = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.groups.isEmpty {
                    LoadingOverlay(message: "Loading groups…")
                } else if vm.groups.isEmpty {
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
            .refreshable { await vm.refresh() }
        }
        .errorAlert(error: $vm.error)
    }

    private var groupList: some View {
        List {
            ForEach(vm.groups) { group in
                NavigationLink(value: group) {
                    groupRow(group)
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

    private func groupRow(_ group: BillGroup) -> some View {
        HStack(spacing: XBillSpacing.md) {
            Text(group.emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.brandSurface)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.xbillBodyLarge)
                    .foregroundStyle(Color.textPrimary)
                Text("\(group.currency) · \(group.createdAt.shortFormatted)")
                    .font(.xbillBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, XBillSpacing.xs)
    }
}

#Preview {
    GroupListView(vm: HomeViewModel())
}

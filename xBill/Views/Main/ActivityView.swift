import SwiftUI

struct ActivityView: View {
    @Bindable var vm: ActivityViewModel

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.items.isEmpty {
                    LoadingOverlay(message: "Loading activity…")
                } else if vm.items.isEmpty {
                    EmptyStateView(
                        icon: "clock.fill",
                        title: "No Activity Yet",
                        message: "Your recent expense activity across all groups will appear here."
                    )
                } else {
                    activityList
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.navBarBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
        .errorAlert(item: $vm.errorAlert)
    }

    // MARK: - Grouped list

    private var groupedItems: [(header: String, items: [ActivityItem])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: vm.items) { item -> String in
            if calendar.isDateInToday(item.createdAt)     { return "TODAY" }
            if calendar.isDateInYesterday(item.createdAt) { return "YESTERDAY" }
            return item.createdAt.shortFormatted.uppercased()
        }
        return grouped
            .map { (header: $0.key, items: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.items.first?.createdAt ?? .distantPast > $1.items.first?.createdAt ?? .distantPast }
    }

    private var activityList: some View {
        List {
            ForEach(groupedItems, id: \.header) { section in
                Section {
                    ForEach(section.items) { item in
                        ActivityRowView(item: item)
                            .listRowBackground(Color.bgCard)
                    }
                } header: {
                    Text(section.header)
                        .font(.xbillCaptionBold)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.bgSecondary)
        .listRowSeparatorTint(Color.separator)
    }
}

// MARK: - Activity Row

private struct ActivityRowView: View {
    let item: ActivityItem

    var body: some View {
        HStack(alignment: .top, spacing: XBillSpacing.md) {
            CategoryIconView(category: item.category, size: XBillIcon.categorySize)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.expenseTitle)
                    .font(.xbillBodyMedium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                // Single-line subtitle: "GroupName · Paid by username"
                Text("\(item.groupEmoji) \(item.groupName) · Paid by \(item.payerName)")
                    .font(.xbillCaption)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)

                Text(item.createdAt, format: .relative(presentation: .named))
                    .font(.xbillCaption)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            AmountBadge(amount: item.amount, direction: .total, currency: item.currency)
        }
        .padding(.vertical, XBillSpacing.xs)
    }
}

#Preview {
    ActivityView(vm: ActivityViewModel())
}

//
//  QuickAddExpenseSheet.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

// MARK: - QuickAddExpenseSheet

/// Shown when the user triggers the "Add Expense" or "Scan Receipt" Home Screen Quick Action.
/// Lets the user pick a group, then presents AddExpenseView for that group.
struct QuickAddExpenseSheet: View {
    let groups: [BillGroup]
    let currentUserID: UUID
    let startWithScan: Bool
    let onSaved: () async -> Void

    @State private var selectedGroup: BillGroup?
    @State private var members: [User] = []
    @State private var isLoadingMembers = false
    @State private var showAddExpense = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                if groups.isEmpty {
                    EmptyStateView(
                        icon: "person.3.fill",
                        title: "No Groups",
                        message: "Create a group first before adding expenses."
                    )
                } else {
                    List(groups) { group in
                        Button {
                            Task {
                                isLoadingMembers = true
                                members = (try? await GroupService.shared.fetchMembers(groupID: group.id)) ?? []
                                isLoadingMembers = false
                                selectedGroup = group
                                showAddExpense = true
                            }
                        } label: {
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
                                    Text(group.currency)
                                        .font(.xbillBodySmall)
                                        .foregroundStyle(Color.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Color.textTertiary)
                            }
                            .padding(.vertical, XBillSpacing.xs)
                        }
                        .listRowBackground(Color.bgCard)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .listRowSeparatorTint(Color.separator)
                }
            }
            .navigationTitle(startWithScan ? "Scan Receipt" : "Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .overlay {
                if isLoadingMembers { LoadingOverlay(message: "Loading…") }
            }
            .sheet(isPresented: $showAddExpense) {
                if let group = selectedGroup {
                    AddExpenseView(
                        group: group,
                        members: members,
                        currentUserID: currentUserID,
                        startWithScan: startWithScan,
                        onSaved: {
                            await onSaved()
                            dismiss()
                        }
                    )
                }
            }
        }
    }
}

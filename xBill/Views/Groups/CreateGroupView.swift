import SwiftUI

struct CreateGroupView: View {
    let onCreated: (BillGroup) async -> Void

    @State private var name: String = ""
    @State private var selectedEmoji: String = "💸"
    @State private var currency: String = "USD"
    @State private var inviteEmail: String = ""
    @State private var isLoading: Bool = false
    @State private var error: AppError?

    @Environment(\.dismiss) private var dismiss

    private let emojis = [
        "💸", "💰", "🍕", "🍺", "🏠", "✈️", "🎮", "🎬", "🛒", "🏋️",
        "🎵", "🚗", "💊", "📚", "🌮", "🍣", "⚽", "🎯", "🎁", "🧳"
    ]

    private let currencies = ["USD", "EUR", "GBP", "INR", "AUD", "CAD", "SGD", "JPY"]

    var canCreate: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                // Name
                Section("Group Name") {
                    TextField("e.g. Weekend Trip", text: $name)
                        .autocorrectionDisabled()
                }

                // Emoji picker
                Section("Icon") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                        spacing: 8
                    ) {
                        ForEach(emojis, id: \.self) { emoji in
                            Text(emoji)
                                .font(.title2)
                                .frame(width: 52, height: 52)
                                .liquidGlass(
                                    fallback: selectedEmoji == emoji
                                        ? Color.accentColor.opacity(0.18)
                                        : Color(.systemGray6),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(
                                            selectedEmoji == emoji ? Color.accentColor : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                                .onTapGesture { selectedEmoji = emoji }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Currency
                Section("Currency") {
                    Picker("Currency", selection: $currency) {
                        ForEach(currencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Invite
                Section {
                    TextField("friend@email.com", text: $inviteEmail)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Invite by Email")
                } footer: {
                    Text("You can also invite people after the group is created.")
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Create") {
                            Task { await create() }
                        }
                        .disabled(!canCreate)
                    }
                }
            }
        }
        .errorAlert(error: $error)
    }

    // MARK: - Action

    private func create() async {
        guard let userID = await AuthService.shared.currentUserID else {
            error = .unauthenticated
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let group = try await GroupService.shared.createGroup(
                name: name.trimmingCharacters(in: .whitespaces),
                emoji: selectedEmoji,
                currency: currency,
                createdBy: userID
            )
            await onCreated(group)
            dismiss()
        } catch {
            self.error = AppError.from(error)
        }
    }
}

#Preview {
    CreateGroupView { _ in }
}

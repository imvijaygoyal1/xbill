//
//  ContactPickerView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI
import Contacts
import ContactsUI

// MARK: - ContactPickerRepresentable

/// Shared wrapper around CNContactPickerViewController.
/// Used by both InviteMembersView and AddFriendView.
struct ContactPickerRepresentable: UIViewControllerRepresentable {
    let onPickedEmails: ([String]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPickedEmails: onPickedEmails) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.displayedPropertyKeys = [CNContactEmailAddressesKey]
        picker.predicateForEnablingContact = NSPredicate(format: "emailAddresses.@count > 0")
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPickedEmails: ([String]) -> Void
        init(onPickedEmails: @escaping ([String]) -> Void) {
            self.onPickedEmails = onPickedEmails
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let emails = contacts.flatMap { $0.emailAddresses.map { ($0.value as String).lowercased() } }
            onPickedEmails(emails)
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let emails = contact.emailAddresses.map { ($0.value as String).lowercased() }
            onPickedEmails(emails)
        }
    }
}

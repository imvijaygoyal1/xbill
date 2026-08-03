//
//  ExportShareItem.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Extracted from `GroupDetailView.swift`, which held five top-level types in 1,197 lines and had
//  already been split into `baseContent`/`lifecycleContent`/`decoratedContent` — not for clarity
//  but to escape a Swift type-checker timeout. A file that large is also why logic tends to live
//  in view bodies where no unit test can reach it.
//

import SwiftUI

struct ExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

extension String {
    var sanitizedForFilename: String {
        self.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
            .lowercased()
    }
}

#Preview {
    NavigationStack {
        GroupDetailView(
            group: BillGroup(
                id: UUID(), name: "Weekend Trip", emoji: "✈️",
                createdBy: UUID(), isArchived: false,
                currency: "USD", createdAt: Date()
            ),
            currentUserID: UUID()
        )
    }
}

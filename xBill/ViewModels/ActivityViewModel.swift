//
//  ActivityViewModel.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Observation

@Observable
@MainActor
final class ActivityViewModel {
    var items: [ActivityItem] = []
    var isLoading: Bool = false
    var errorAlert: ErrorAlert?

    private let service = ActivityService.shared
    private let auth    = AuthService.shared

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let userID = await auth.currentUserID else { throw AppError.unauthenticated }
            items = try await service.fetchRecentActivity(userID: userID)
        } catch {
            self.errorAlert = ErrorAlert(title: "Something went wrong", message: error.localizedDescription)
        }
    }
}

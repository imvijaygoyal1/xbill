import Foundation
import Observation

@Observable
@MainActor
final class ActivityViewModel {
    var items: [ActivityItem] = []
    var isLoading: Bool = false
    var error: AppError?

    private let service = ActivityService.shared
    private let auth    = AuthService.shared

    func load() async {
        isLoading = true
        error     = nil
        defer { isLoading = false }
        do {
            guard let userID = await auth.currentUserID else { throw AppError.unauthenticated }
            items = try await service.fetchRecentActivity(userID: userID)
        } catch {
            self.error = AppError.from(error)
        }
    }
}

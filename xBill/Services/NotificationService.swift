//
//  NotificationService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import UserNotifications

// MARK: - NotificationService

final class NotificationService: Sendable {
    static let shared = NotificationService()
    private init() {}

    static let preferenceConfiguredKey = "prefPushConfiguredAfterPermission"
    static let expensePreferenceKey = "prefPushExpense"
    static let settlementPreferenceKey = "prefPushSettlement"
    static let commentPreferenceKey = "prefPushComment"

    // MARK: - Authorization

    func requestAuthorization() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        return try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func isPushAuthorized() async -> Bool {
        await authorizationStatus().allowsPushRegistration
    }

    func enableDefaultPreferencesAfterPermissionIfNeeded(defaults: UserDefaults = CacheService.defaults) {
        guard !defaults.bool(forKey: Self.preferenceConfiguredKey) else { return }
        defaults.set(true, forKey: Self.expensePreferenceKey)
        defaults.set(true, forKey: Self.settlementPreferenceKey)
        defaults.set(true, forKey: Self.commentPreferenceKey)
        defaults.set(true, forKey: Self.preferenceConfiguredKey)
    }

    // MARK: - Local Notifications

    func scheduleSettlementReminder(
        for suggestion: SettlementSuggestion,
        triggerAfter seconds: TimeInterval = 86400
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Payment Reminder"
        content.body = "You owe \(suggestion.toName) \(suggestion.amount.formatted(currencyCode: suggestion.currency))"
        content.sound = .default
        content.userInfo = ["settlementId": suggestion.id.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(
            identifier: "settlement-\(suggestion.id.uuidString)",
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Cancel

    func cancelNotification(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Badge

    @MainActor
    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
    }
}

extension UNAuthorizationStatus {
    var allowsPushRegistration: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }
}

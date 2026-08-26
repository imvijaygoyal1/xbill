//
//  NotificationService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import UserNotifications

// MARK: - NotificationService

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    // The `prefPush*` UserDefaults keys were removed with PUSH-01. They were read on the SENDER's
    // device to decide whether OTHER people were notified; the recipient's own preference now
    // lives server-side and is cached by `NotificationPreferencesService` under different keys.

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

    // PUSH-01: `enableDefaultPreferencesAfterPermissionIfNeeded` is gone. It seeded three
    // UserDefaults keys that nothing reads any more — preferences live in
    // `public.notification_preferences`, where the defaults are all-on and a missing row already
    // means on, so there is no moment at which anything needs enabling. A function that sets state
    // no reader consults is worse than none: it reads as consent handling and is not.

    // MARK: - Local Notifications

    func scheduleSettlementReminder(
        for suggestion: SettlementSuggestion,
        triggerAfter seconds: TimeInterval = 86400
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Payment Reminder"
        content.body = "You owe \(suggestion.toName) \(suggestion.amount.formatted(currencyCode: suggestion.currency))"
        content.sound = .default
        content.userInfo = ["settlementId": suggestion.id]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(
            identifier: "settlement-\(suggestion.id)",
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

    @MainActor
    func setBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, count)) { _ in }
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

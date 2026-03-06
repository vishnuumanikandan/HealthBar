//
//  NotificationManager.swift
//  HealthBar
//
//  Created by Claude on 2/2/26.
//

import Foundation
import UserNotifications

/// Manages local notifications for the app
///
/// Currently handles:
/// - Daily mood check reminder at 7pm
@Observable
final class NotificationManager {

    // MARK: - Singleton

    /// Shared instance for app-wide access
    static let shared = NotificationManager()

    // MARK: - Properties

    /// Whether notification permission has been granted
    private(set) var isAuthorized = false

    // MARK: - Initialization

    private init() {}

    // MARK: - Permission

    /// Requests notification permission from the user
    /// - Returns: True if permission was granted
    @discardableResult
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            isAuthorized = false
            return false
        }
    }

    /// Checks current authorization status
    func checkAuthorizationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Mood Check Notification

    /// Identifier for mood check notifications
    private let moodCheckIdentifier = "dailyMoodCheck"

    /// Schedules a daily notification at 7pm for mood check
    ///
    /// Only schedules if mood check is enabled in settings.
    func scheduleMoodCheckNotification() {
        guard SettingsManager.shared.dailyMoodCheckEnabled else {
            cancelMoodCheckNotification()
            return
        }

        let center = UNUserNotificationCenter.current()

        // Remove existing to avoid duplicates
        center.removePendingNotificationRequests(withIdentifiers: [moodCheckIdentifier])

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "How are you feeling?"
        content.body = "Take a moment to log your mood for today."
        content.sound = .default

        // Schedule for 7pm daily
        var dateComponents = DateComponents()
        dateComponents.hour = 19
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: moodCheckIdentifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error = error {
                print("Failed to schedule mood notification: \(error)")
            }
        }
    }

    /// Cancels the mood check notification
    func cancelMoodCheckNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [moodCheckIdentifier])
    }

    /// Updates mood notification based on current settings
    func updateMoodNotificationIfNeeded() {
        if SettingsManager.shared.dailyMoodCheckEnabled {
            scheduleMoodCheckNotification()
        } else {
            cancelMoodCheckNotification()
        }
    }
}

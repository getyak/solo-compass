import Foundation
import UserNotifications

/// Manages local push notifications for geofence-triggered check-in prompts.
/// No APNs server required — all notifications are local.
@MainActor
@Observable
public final class NotificationService {
    public static let shared = NotificationService()

    public private(set) var isAuthorized: Bool = false

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Authorization

    /// Asks the traveler for permission to send check-in and safety notifications.
    public func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
        } catch {
            isAuthorized = false
        }
    }

    /// Refreshes whether notifications are currently allowed for the app.
    public func checkAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Scheduling

    /// Schedule a local notification prompting a check-in.
    /// Respects `preferences.isQuietHours` — delays to morning if quiet hours are active.
    public func scheduleCheckInPrompt(
        experienceId: String,
        experienceTitle: String,
        preferences: UserPreferences
    ) async {
        guard isAuthorized, preferences.notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("notification.checkin.title", comment: "Check-in notification title")
        content.body = String(
            format: NSLocalizedString("notification.checkin.body", comment: "Check-in notification body"),
            experienceTitle
        )
        content.sound = .default
        content.userInfo = ["experienceId": experienceId]

        let identifier = "checkin-\(experienceId)"
        await center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let delay: TimeInterval = preferences.isQuietHours
            ? secondsUntilMorning(quietHoursEnd: preferences.quietHoursEnd)
            : 3

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            // Non-critical — the in-app banner is the primary check-in UI.
        }
    }

    /// Remove a pending notification once the user has already acted via the in-app banner.
    public func cancelCheckInNotification(for experienceId: String) async {
        let identifier = "checkin-\(experienceId)"
        await center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: - Helpers

    private func secondsUntilMorning(quietHoursEnd: Int) -> TimeInterval {
        let cal = Calendar.current
        let now = Date()
        var components = cal.dateComponents([.year, .month, .day], from: now)
        components.hour = quietHoursEnd
        components.minute = 0
        components.second = 0
        if let morning = cal.date(from: components) {
            let diff = morning.timeIntervalSince(now)
            return diff > 0 ? diff : diff + 86_400
        }
        return Double(quietHoursEnd) * 3600
    }
}

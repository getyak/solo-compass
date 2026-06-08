import Foundation
import UserNotifications

/// Manages local push notifications for geofence-triggered check-in prompts.
/// No APNs server required — all notifications are local.
@MainActor
@Observable
public final class NotificationService {
    public static let shared = NotificationService()

    public private(set) var isAuthorized: Bool = false

    /// US-023: a deep link emitted from an incoming APNs payload, observed by the
    /// UI (CompassMapView) to present the matching surface. `nil` once consumed.
    /// Currently only `.friendRequestInbox` is produced.
    public enum DeepLink: Equatable {
        /// Open the friend-request inbox (a `friend_request` push arrived).
        /// `requestId` identifies the specific pending request, when known.
        case friendRequestInbox(requestId: String?)
    }

    /// The latest deep link awaiting presentation. The UI sets it back to `nil`
    /// after routing, so a re-observation does not re-navigate.
    public var pendingDeepLink: DeepLink?

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - US-023: Remote (APNs) payload routing

    /// Route an incoming APNs payload to a `pendingDeepLink`.
    ///
    /// Recognizes the `friend-request-notify` payload
    /// (`{ type: "friend_request", requestId, ... }`) and surfaces a
    /// `.friendRequestInbox` deep link. Unknown payloads are ignored.
    public func handleRemotePayload(_ userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return }
        switch type {
        case "friend_request":
            let requestId = userInfo["requestId"] as? String
            pendingDeepLink = .friendRequestInbox(requestId: requestId)
        default:
            break
        }
    }

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

    /// US-020: notify a friend that the host pulled them straight into a
    /// recruiting route (no approval step). Local notification only — no APNs
    /// server. Fires shortly after the host taps Invite; the invited friend's
    /// device surfaces a "you're in" banner deep-linking the route.
    public func scheduleRouteJoinNotification(
        routeId: String,
        routeTitle: String,
        hostId: String
    ) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString(
            "notification.route.join.title",
            comment: "Route join notification title"
        )
        content.body = String(
            format: NSLocalizedString(
                "notification.route.join.body",
                comment: "Route join notification body — host invited you into a route"
            ),
            hostId,
            routeTitle
        )
        content.sound = .default
        content.userInfo = ["routeId": routeId]

        let identifier = "route-join-\(routeId)"
        await center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            // Non-critical — membership is already persisted; the banner is a nicety.
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

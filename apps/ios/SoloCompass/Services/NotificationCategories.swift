import Foundation
import UserNotifications

/// Notification categories + quick actions for the SoloCompass companion /
/// route flows (US-026). Registered once at launch so the system attaches the
/// "我已出发 / 查看路线" and "接受 / 查看申请" buttons to the matching banners.
///
/// Design source: the lock-screen stack in `island_notif.jsx` — a time-sensitive
/// departure reminder with two actions, and a host-facing join request with an
/// inline accept. Tapping an action routes through `NotificationService`'s
/// userInfo handling just like a banner tap.
public enum SCNotificationCategory {
    /// 出发提醒 (time-sensitive) — "我已出发" / "查看路线".
    public static let departure = "sc.departure"
    /// 加入申请 (host view) — "接受" / "查看申请".
    public static let joinRequest = "sc.joinRequest"

    // Action identifiers (handled in NotificationService.handleActionResponse).
    public static let actionDeparted    = "sc.action.departed"
    public static let actionViewRoute   = "sc.action.viewRoute"
    public static let actionAccept      = "sc.action.accept"
    public static let actionViewRequest = "sc.action.viewRequest"

    /// Build and register all categories. Idempotent — safe to call on every
    /// launch; the last `setNotificationCategories` wins.
    public static func registerAll(on center: UNUserNotificationCenter = .current()) {
        let departed = UNNotificationAction(
            identifier: actionDeparted,
            title: NSLocalizedString("notification.action.departed", comment: "I'm on my way"),
            options: []
        )
        let viewRoute = UNNotificationAction(
            identifier: actionViewRoute,
            title: NSLocalizedString("notification.action.viewRoute", comment: "View route"),
            options: [.foreground]
        )
        let accept = UNNotificationAction(
            identifier: actionAccept,
            title: NSLocalizedString("notification.action.accept", comment: "Accept join request"),
            options: [.authenticationRequired]
        )
        let viewRequest = UNNotificationAction(
            identifier: actionViewRequest,
            title: NSLocalizedString("notification.action.viewRequest", comment: "View request"),
            options: [.foreground]
        )

        let departureCategory = UNNotificationCategory(
            identifier: departure,
            actions: [departed, viewRoute],
            intentIdentifiers: [],
            options: []
        )
        let joinCategory = UNNotificationCategory(
            identifier: joinRequest,
            actions: [accept, viewRequest],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([departureCategory, joinCategory])
    }
}

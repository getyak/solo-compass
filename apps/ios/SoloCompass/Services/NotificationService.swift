import Foundation
import UserNotifications

/// Manages local push notifications for geofence-triggered check-in prompts.
/// No APNs server required — all notifications are local.
@MainActor
@Observable
public final class NotificationService {
    public static let shared = NotificationService()

    public private(set) var isAuthorized: Bool = false

    /// US-023 / US-024: a deep link emitted from an incoming APNs payload,
    /// observed by the UI (CompassMapView) to present the matching surface.
    /// `nil` once consumed.
    public enum DeepLink: Equatable {
        /// Open the friend-request inbox (a `friend_request` push arrived).
        /// `requestId` identifies the specific pending request, when known.
        case friendRequestInbox(requestId: String?)
        /// US-024: open the matching ChatView for `conversationId` (a `message`
        /// push arrived). The conversation lives inside the personal hub's
        /// Messages list, which auto-opens the thread once surfaced.
        case chatConversation(conversationId: String)
        /// Open the experience detail sheet for `experienceId`. Routed from
        /// `solocompass://experience/<id>` shared via the iOS share sheet or
        /// pasted into Safari/Messages.
        case experienceDetail(experienceId: String)
        /// Open the route detail / preview for `routeId`. Routed from
        /// `solocompass://route/<id>`.
        case routePreview(routeId: String)
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
    /// (`{ type: "friend_request", requestId, ... }`) → `.friendRequestInbox`,
    /// and the `message-notify` payload
    /// (`{ type: "message", conversationId, senderHandle, preview }`) →
    /// `.chatConversation`. Unknown payloads are ignored.
    /// Route a `solocompass://` URL (custom scheme registered in Info.plist
    /// CFBundleURLTypes) into the same `pendingDeepLink` mechanism that APNs
    /// payloads use. Recognized paths:
    ///   - `experience/<id>` → `.experienceDetail`
    ///   - `route/<id>`      → `.routePreview`
    ///   - `chat/<id>`       → `.chatConversation`
    ///   - `friends`         → `.friendRequestInbox(nil)`
    /// Unknown paths are ignored. Returns true when a link was routed,
    /// false otherwise — handy for tests / telemetry.
    @discardableResult
    public func handleURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "solocompass" else { return false }
        // URL.host carries the first path segment for opaque-style URLs
        // (solocompass://experience/abc → host="experience", path="/abc").
        let segments = (url.host.map { [$0] } ?? []) + url.pathComponents.filter { $0 != "/" }
        guard let kind = segments.first?.lowercased() else { return false }
        let id = segments.dropFirst().joined(separator: "/")
        switch kind {
        case "experience" where !id.isEmpty:
            pendingDeepLink = .experienceDetail(experienceId: id)
            return true
        case "route" where !id.isEmpty:
            pendingDeepLink = .routePreview(routeId: id)
            return true
        case "chat" where !id.isEmpty:
            pendingDeepLink = .chatConversation(conversationId: id)
            return true
        case "friends":
            pendingDeepLink = .friendRequestInbox(requestId: nil)
            return true
        default:
            return false
        }
    }

    public func handleRemotePayload(_ userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return }
        switch type {
        case "friend_request":
            let requestId = userInfo["requestId"] as? String
            pendingDeepLink = .friendRequestInbox(requestId: requestId)
        case "message":
            // US-024: tapping a message push opens the matching ChatView. A
            // missing conversationId can't be routed, so it's ignored.
            guard let conversationId = userInfo["conversationId"] as? String,
                  !conversationId.isEmpty else { return }
            pendingDeepLink = .chatConversation(conversationId: conversationId)
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

    // MARK: - US-026: companion / route lock-screen notifications
    //
    // The five scenarios from the design's lock-screen stack (island_notif.jsx).
    // All local — no APNs. DayPage voice: structured, sentence-case, no emoji,
    // the result stated in one line.

    /// ① AI「此刻」提示 — e.g. "日落将至 · 步行 7 分钟可达 湄公河观景点". Default
    /// interruption level; this is a gentle nudge, not urgent.
    public func scheduleAINowHint(title: String, body: String, deepLinkExperienceId: String? = nil) async {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let id = deepLinkExperienceId { content.userInfo = ["experienceId": id] }
        await deliver(content, id: "ai-now-\(deepLinkExperienceId ?? UUID().uuidString)", after: 2)
    }

    /// ② 出发提醒 (time-sensitive) — "30 分钟后集合" with "我已出发 / 查看路线"
    /// quick actions. Time-sensitive so it can break through Focus when the
    /// group is about to set off. Fires at `fireDate` (e.g. 30 min before the
    /// group's departure); a past/imminent `fireDate` is clamped to ~now.
    public func scheduleDepartureReminder(
        routeId: String,
        title: String,
        body: String,
        fireDate: Date
    ) async {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = SCNotificationCategory.departure
        content.userInfo = ["routeId": routeId, "kind": "departure"]
        let seconds = max(1, fireDate.timeIntervalSinceNow)
        await deliver(content, id: "departure-\(routeId)", after: seconds)
    }

    /// ③ 加入申请 (host view) — "Yuna 想加入你的路线" with "接受 / 查看申请".
    public func scheduleJoinRequestNotification(
        routeId: String,
        requestId: String,
        title: String,
        body: String
    ) async {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = SCNotificationCategory.joinRequest
        content.userInfo = ["routeId": routeId, "requestId": requestId, "kind": "joinRequest"]
        await deliver(content, id: "join-\(requestId)", after: 2)
    }

    /// ④ 群聊新消息 — "Lin: 中午 11:30 我们转场 Sapa…". Routes to the chat thread.
    public func scheduleGroupMessage(
        conversationId: String,
        senderName: String,
        preview: String
    ) async {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = senderName
        content.body = preview
        content.sound = .default
        // Group by conversation so threads stack on the lock screen (the design's
        // "+2 条" stacked notification).
        content.threadIdentifier = "conv-\(conversationId)"
        content.userInfo = ["type": "message", "conversationId": conversationId]
        await deliver(content, id: "msg-\(conversationId)-\(UUID().uuidString)", after: 1)
    }

    /// ⑤ 已成团 — low-priority result confirmation, one line.
    public func scheduleGroupFormed(routeId: String, title: String, body: String) async {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .passive
        content.userInfo = ["routeId": routeId, "kind": "groupFormed"]
        await deliver(content, id: "formed-\(routeId)", after: 2)
    }

    /// US-026: route a quick-action tap. "我已出发" is fire-and-forget (no nav);
    /// "查看路线" / "接受" / "查看申请" deep-link into the matching surface via the
    /// existing pendingDeepLink mechanism.
    public func handleActionResponse(actionIdentifier: String, userInfo: [AnyHashable: Any]) {
        switch actionIdentifier {
        case SCNotificationCategory.actionDeparted:
            // Acknowledged — no navigation. (A future story can mark the member
            // as en route in the group thread.)
            break
        case SCNotificationCategory.actionAccept, SCNotificationCategory.actionViewRequest:
            let requestId = userInfo["requestId"] as? String
            pendingDeepLink = .friendRequestInbox(requestId: requestId)
        case SCNotificationCategory.actionViewRoute:
            // The map observes pendingDeepLink; a route deep link reuses the
            // chat-conversation channel when a group thread exists, else falls
            // through to a plain tap (handled by handleRemotePayload).
            handleRemotePayload(userInfo)
        default:
            handleRemotePayload(userInfo)
        }
    }

    /// Shared scheduling tail — removes any prior request with the same id, then
    /// adds a short-delay one-shot trigger. Errors are non-critical (the in-app
    /// surface is primary).
    private func deliver(_ content: UNMutableNotificationContent, id: String, after seconds: TimeInterval) async {
        await center.removePendingNotificationRequests(withIdentifiers: [id])
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
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

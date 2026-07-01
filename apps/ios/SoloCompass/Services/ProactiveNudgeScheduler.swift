import Foundation
import Observation
import UserNotifications
import os

/// P2.6 #260 – #264 + P2.4 #244: business-layer scheduler that sits on
/// top of `NotificationService` (which already owns permission +
/// UNUserNotificationCenter registration + deep-link routing).
///
/// Responsibilities:
/// - **Rate limit** — a shared per-day nudge budget (default 3/day)
///   consumed across every nudge type so the user never gets more than
///   3 taps on the shoulder in a day, no matter how many triggers fire.
/// - **Business scheduling** — the three nudge kinds (lonely hours,
///   morning city omen, capsule arrival) each have their own scheduling
///   contract; this file encodes those.
/// - **Opt-out honoured** — every schedule call bails cleanly when the
///   corresponding UserDefaults toggle is off.
///
/// This service is intentionally thin: real notification content lives
/// upstream (OmenComposeService for morning, CapsuleStore for capsule).
/// The scheduler decides **whether** to fire and **when**, then hands
/// the content off.
@MainActor
@Observable
public final class ProactiveNudgeScheduler {

    public static let shared = ProactiveNudgeScheduler()

    /// Total nudges the user is willing to receive per calendar day.
    public var dailyBudget: Int = 3

    /// Lonely-window default (user can override in Settings).
    public var lonelyHoursStart: Int = 17
    public var lonelyHoursEnd: Int = 21

    private let center: UNUserNotificationCenter
    private let calendar: Calendar
    private let log = OSLog(subsystem: "com.solocompass.app", category: "Nudge")

    public enum Toggle: String {
        case lonelyHours = "com.solocompass.nudge.lonelyHours.enabled.v1"
        case cityOmen    = "com.solocompass.nudge.cityOmen.enabled.v1"
        case capsule     = "com.solocompass.nudge.capsule.enabled.v1"
    }

    public init(
        center: UNUserNotificationCenter = .current(),
        calendar: Calendar = Calendar.current
    ) {
        self.center = center
        self.calendar = calendar
    }

    // MARK: - Toggles

    public func isEnabled(_ toggle: Toggle) -> Bool {
        UserDefaults.standard.object(forKey: toggle.rawValue) as? Bool ?? true
    }

    public func setEnabled(_ toggle: Toggle, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: toggle.rawValue)
    }

    // MARK: - Rate limit

    /// Shared per-day nudge counter. Returns whether we can consume one.
    @discardableResult
    public func consumeDailyBudget(now: Date = Date()) -> Bool {
        let key = Self.budgetKey(for: now, calendar: calendar)
        let used = UserDefaults.standard.integer(forKey: key)
        if used >= dailyBudget { return false }
        UserDefaults.standard.set(used + 1, forKey: key)
        return true
    }

    static func budgetKey(for date: Date, calendar: Calendar) -> String {
        let comp = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "com.solocompass.nudge.dailycount.%04d-%02d-%02d.v1",
            comp.year ?? 0, comp.month ?? 0, comp.day ?? 0
        )
    }

    // MARK: - P2.6 #261 lonely-hour nudge

    @discardableResult
    public func scheduleLonelyNudge(
        anchorTitle: String,
        anchorExperienceId: String,
        now: Date = Date()
    ) async -> Bool {
        guard isEnabled(.lonelyHours) else { return false }
        let hour = calendar.component(.hour, from: now)
        guard hour >= lonelyHoursStart && hour < lonelyHoursEnd else { return false }
        guard consumeDailyBudget(now: now) else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Small idea for now."
        content.body = "\(anchorTitle) is about a walk away."
        content.userInfo = [
            "kind": "lonely_hours",
            "experience_id": anchorExperienceId,
        ]
        content.categoryIdentifier = "solo_compass_nudge"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        do {
            try await center.add(request)
            return true
        } catch {
            os_log("Nudge: lonely add failed %{public}@", log: log, type: .error, String(describing: error))
            return false
        }
    }

    // MARK: - P2.6 #262 morning city-omen nudge

    @discardableResult
    public func scheduleMorningOmen(
        line: String,
        deliverAtHour hour: Int = 7,
        now: Date = Date()
    ) async -> Bool {
        guard isEnabled(.cityOmen) else { return false }
        let today = calendar.startOfDay(for: now)
        let stampedKey = "com.solocompass.nudge.omen.sent.\(Self.dayKey(for: today, calendar: calendar))"
        if UserDefaults.standard.bool(forKey: stampedKey) { return false }
        guard consumeDailyBudget(now: now) else { return false }
        UserDefaults.standard.set(true, forKey: stampedKey)

        let content = UNMutableNotificationContent()
        content.title = "Today"
        content.body = line
        content.userInfo = ["kind": "city_omen"]

        var dateComps = calendar.dateComponents([.year, .month, .day], from: today)
        dateComps.hour = hour
        dateComps.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComps, repeats: false)
        let request = UNNotificationRequest(identifier: "omen.\(stampedKey)", content: content, trigger: trigger)

        do {
            try await center.add(request)
            return true
        } catch {
            os_log("Nudge: omen add failed %{public}@", log: log, type: .error, String(describing: error))
            return false
        }
    }

    // MARK: - P2.6 #263 capsule proximity nudge

    @discardableResult
    public func scheduleCapsuleProximityNudge(
        capsulePreview: String,
        experienceId: String,
        now: Date = Date()
    ) async -> Bool {
        guard isEnabled(.capsule) else { return false }
        guard consumeDailyBudget(now: now) else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Something you left here."
        content.body = capsulePreview
        content.userInfo = [
            "kind": "capsule",
            "experience_id": experienceId,
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "capsule.\(experienceId)", content: content, trigger: trigger)

        do {
            try await center.add(request)
            return true
        } catch {
            os_log("Nudge: capsule add failed %{public}@", log: log, type: .error, String(describing: error))
            return false
        }
    }

    // MARK: - P2.4 #244 year-end capsule inventory nudge

    @discardableResult
    public func scheduleYearEndCapsuleReview(
        buriedThisYear: Int,
        ripenNextYear: Int,
        now: Date = Date()
    ) async -> Bool {
        guard buriedThisYear + ripenNextYear > 0 else { return false }
        let year = calendar.component(.year, from: now)
        let stamped = "com.solocompass.nudge.yearReview.\(year)"
        if UserDefaults.standard.bool(forKey: stamped) { return false }
        guard consumeDailyBudget(now: now) else { return false }
        UserDefaults.standard.set(true, forKey: stamped)

        let content = UNMutableNotificationContent()
        content.title = "Your year, buried."
        content.body = "You buried \(buriedThisYear) capsules this year. \(ripenNextYear) ripen next year."
        content.userInfo = ["kind": "year_end_capsule_review"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "yearReview.\(year)", content: content, trigger: trigger)

        do {
            try await center.add(request)
            return true
        } catch {
            os_log("Nudge: year review add failed %{public}@", log: log, type: .error, String(describing: error))
            return false
        }
    }

    // MARK: - Helpers

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let comp = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comp.year ?? 0, comp.month ?? 0, comp.day ?? 0)
    }
}

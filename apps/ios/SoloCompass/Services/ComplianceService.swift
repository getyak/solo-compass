import Foundation
import Observation

// MARK: - City OS v2 · visa / 183-day tax compliance (PRD §5.2)
//
// The one part of the landing kit that is self-computed, offline-usable, and
// therefore rendered in mono big digits — it must be exactly right. All math
// lives in `ComplianceMath` (pure, calendar-injected) so tests can pin every
// boundary; `ComplianceService` is a thin @MainActor reader over
// `UserPreferences`.

/// Pure visa / tax-day arithmetic. Day counting is calendar-day based
/// (startOfDay to startOfDay) and treats the entry day as day 1, matching the
/// "落地签 30 天 · 已停留 3 天 · 剩 27 天" convention in the PRD.
public enum ComplianceMath {
    /// The tax-residency threshold in days (the "183-day rule").
    public static let taxLineDays = 183

    /// Days stayed including the entry day: entering today = 1.
    /// Returns 0 when `entryDate` is in the future.
    public static func daysStayed(entryDate: Date, now: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: entryDate)
        let today = calendar.startOfDay(for: now)
        guard let diff = calendar.dateComponents([.day], from: start, to: today).day, diff >= 0 else {
            return 0
        }
        return diff + 1
    }

    /// Visa days remaining: length − stayed. Negative means overstayed.
    public static func visaDaysRemaining(entryDate: Date, visaLengthDays: Int, now: Date, calendar: Calendar = .current) -> Int {
        visaLengthDays - daysStayed(entryDate: entryDate, now: now, calendar: calendar)
    }

    /// Days left before crossing the 183-day tax-residency line, floored at 0.
    public static func taxDaysRemaining(daysStayed: Int) -> Int {
        max(0, taxLineDays - daysStayed)
    }

    /// The compliance banner surfaces only when the situation is critical:
    /// 7 days or fewer remaining (including overstay). PRD §4.3 interruption
    /// budget applies on top of this.
    public static func shouldShowBanner(daysRemaining: Int) -> Bool {
        daysRemaining <= 7
    }
}

/// Reads the traveler's locally stored entry date + visa length and exposes
/// render-ready compliance state. Never talks to the network — privacy-first
/// per PRD §5.2 ("纯本地自算").
@MainActor
@Observable
public final class ComplianceService {
    private let preferences: UserPreferences

    /// Creates the service over the given preferences store.
    public init(preferences: UserPreferences) {
        self.preferences = preferences
    }

    /// Snapshot of the visa/tax counters for rendering, nil until the user
    /// has entered their entry date.
    public struct State: Equatable, Sendable {
        /// Days stayed including entry day.
        public let daysStayed: Int
        /// Visa days remaining (negative = overstayed).
        public let visaDaysRemaining: Int
        /// Days until the 183-day tax line, floored at 0.
        public let taxDaysRemaining: Int
        /// Whether the critical banner condition (≤7 days) holds.
        public let isCritical: Bool
    }

    /// Current compliance state, or nil when no entry date is recorded.
    public func state(now: Date = Date()) -> State? {
        guard let entry = preferences.visaEntryDate, let length = preferences.visaLengthDays else {
            return nil
        }
        let stayed = ComplianceMath.daysStayed(entryDate: entry, now: now)
        let remaining = ComplianceMath.visaDaysRemaining(entryDate: entry, visaLengthDays: length, now: now)
        return State(
            daysStayed: stayed,
            visaDaysRemaining: remaining,
            taxDaysRemaining: ComplianceMath.taxDaysRemaining(daysStayed: stayed),
            isCritical: ComplianceMath.shouldShowBanner(daysRemaining: remaining)
        )
    }

    /// Re-schedules (or cancels) the local visa-expiry reminder to match the
    /// user's toggle. Uses a fixed identifier so repeated calls replace the
    /// pending notification instead of stacking.
    public func syncVisaReminder(now: Date = Date()) async {
        guard preferences.visaReminderEnabled,
              let state = state(now: now),
              state.visaDaysRemaining > 0 else {
            await NotificationService.shared.cancelVisaExpiryReminder()
            return
        }
        await NotificationService.shared.scheduleVisaExpiryReminder(daysRemaining: state.visaDaysRemaining)
    }
}

import Foundation
import CoreLocation

/// Sunset signal: nudge viewpoints / parks / rooftop bars to the top of the
/// ranking in the golden window before sunset, fading through blue hour.
///
/// Eligible = `.nature` or `.nightlife`, or any experience tagged
/// `sunset_friendly`. Everything else returns a neutral, zero-weight
/// contribution so sunset timing never bleeds into venues it can't flatter.
///
/// Scoring curve (minutes relative to sunset, eligible venues only):
///   - 90 → 30 min before          → 1.0   (the golden window — "depart now")
///   - 30 →  0 min before          → gaussian decay 1.0 → 0.7
///   -  0 → 30 min after (blue hr)  → 0.6
///   - otherwise                    → 0.4
///
/// Pure & local: it computes sunset from `SolarEvents` (no network), so it never
/// throws. Without a coordinate it can't place the sun → neutral drop-out.
public struct SunsetSignal: NowSignal {
    public static let key = "sunset"
    public static let weight = 0.25

    /// Tag that opts any category into sunset scoring (e.g. a rooftop café).
    static let eligibleTag = "sunset_friendly"

    public init() {}

    public func score(for experience: Experience, at date: Date) async -> NowSignalContribution {
        // Only viewpoint-shaped venues care about sunset timing.
        guard Self.isEligible(experience) else {
            return NowSignalContribution(value: 0.5, weight: 0.0, reason: nil)
        }

        // No coordinate → can't compute the sun's position → neutral drop-out.
        guard let coord = experience.coordinate,
              let sunset = SolarEvents.sunset(at: coord, on: date) else {
            return NowSignalContribution(value: 0.5, weight: 0.0, reason: nil)
        }

        // Positive = before sunset, negative = after.
        let minutesUntil = sunset.timeIntervalSince(date) / 60.0
        let value = Self.value(minutesUntilSunset: minutesUntil)
        let reason = Self.reason(minutesUntilSunset: minutesUntil)
        return NowSignalContribution(value: value, weight: Self.weight, reason: reason)
    }

    // MARK: - Eligibility

    static func isEligible(_ experience: Experience) -> Bool {
        switch experience.category {
        case .nature, .nightlife:
            return true
        default:
            return (experience.userTags ?? []).contains {
                $0.caseInsensitiveCompare(eligibleTag) == .orderedSame
            }
        }
    }

    // MARK: - Scoring

    /// Map "minutes until sunset" to a normalized value. `minutes` is positive
    /// before sunset, negative after.
    static func value(minutesUntilSunset minutes: Double) -> Double {
        switch minutes {
        case 30 ... 90:
            // Golden window: full strength.
            return 1.0
        case 0 ..< 30:
            // Approach: gaussian decay 1.0 (at +30) → 0.7 (at 0).
            // f(m) = 0.7 + 0.3 · exp(-3·((30 - m)/30)²): ≈1.0 at +30, ≈0.715 at 0.
            let x = (30.0 - minutes) / 30.0          // 0 at +30, 1 at 0
            let g = exp(-(x * x) * 3.0)
            return 0.7 + 0.3 * g
        case -30 ..< 0:
            // Blue hour: a flat, slightly-dimmed glow.
            return 0.6
        default:
            // Outside the sunset window entirely.
            return 0.4
        }
    }

    // MARK: - Reason

    /// Localized reason, e.g. `日落 23 分钟后` (depart now), `日落 8 分钟后 · 蓝调时刻`,
    /// or `日落已过 47 分钟`. Returns `nil` far outside the window so we don't nag.
    static func reason(minutesUntilSunset minutes: Double) -> String? {
        switch minutes {
        case 30 ... 90, 0 ..< 30:
            // Before sunset: "sunset in N min".
            let n = Int(minutes.rounded())
            let format = NSLocalizedString(
                "nowscore.sunset.before_min",
                comment: "Sunset is N minutes away"
            )
            return String.localizedStringWithFormat(format, n)
        case -30 ..< 0:
            // Blue hour: "N min after sunset · blue hour".
            let n = Int((-minutes).rounded())
            let format = NSLocalizedString(
                "nowscore.sunset.blue_hour",
                comment: "N minutes after sunset, blue hour"
            )
            return String.localizedStringWithFormat(format, n)
        case ..<(-30):
            // Past blue hour: "sunset was N min ago".
            let n = Int((-minutes).rounded())
            let format = NSLocalizedString(
                "nowscore.sunset.after_min",
                comment: "Sunset was N minutes ago"
            )
            return String.localizedStringWithFormat(format, n)
        default:
            // More than 90 min before sunset — too early to nag.
            return nil
        }
    }
}

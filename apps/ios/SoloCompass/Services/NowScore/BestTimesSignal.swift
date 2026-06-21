import Foundation

/// Timing signal: is `date` inside any of the experience's `bestTimes` windows?
///
/// Mirrors the in-window / out-of-window check that `Experience.nowScore(at:)`
/// shipped with in US-001:
/// - inside an open window → `1.0`
/// - outside every window  → `0.0`
/// - empty `bestTimes`     → `0.5` (neutral; no timing signal to judge by)
public struct BestTimesSignal: NowSignal {
    public static let key = "bestTimes"
    /// **Relative** weight (not absolute) within the active signal set.
    /// `Experience.composeNowScore` divides by the sum of all participating
    /// weights so the final score is always in [0,1] regardless of which
    /// signals are registered. Concretely: with today's two stock signals
    /// (bestTimes 0.4, hourOfDay 0.2) bestTimes carries 0.4/0.6 ≈ 66.7% of
    /// the verdict. Add a third signal at 0.4 and bestTimes naturally drops
    /// to 0.4/1.0 = 40% — the absolute numbers stay stable, the share shifts.
    public static let weight = 0.4

    public init() {}

    public func score(for experience: Experience, at date: Date) async -> NowSignalContribution {
        evaluate(for: experience, at: date)
    }

    /// Synchronous core, also used by `Experience.nowScore(at:)`'s sync path.
    func evaluate(for experience: Experience, at date: Date) -> NowSignalContribution {
        guard !experience.bestTimes.isEmpty else {
            return NowSignalContribution(value: 0.5, weight: Self.weight, reason: "no bestTimes")
        }
        let isOpen = BestTimesSignal.isOpen(experience.bestTimes, at: date)
        return NowSignalContribution(
            value: isOpen ? 1.0 : 0.0,
            weight: Self.weight,
            reason: isOpen ? "in bestTimes window" : "out of bestTimes window"
        )
    }

    /// True when `date` falls inside any window (respecting dayOfWeek / season).
    static func isOpen(_ windows: [TimeWindow], at date: Date) -> Bool {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let weekday = cal.component(.weekday, from: date) - 1 // Sun=0
        let month = cal.component(.month, from: date)
        return windows.contains { window in
            if let days = window.dayOfWeek, !days.isEmpty, !days.contains(weekday) { return false }
            if let seasons = window.season, !seasons.isEmpty, !seasons.contains(month) { return false }
            return window.contains(hour: hour)
        }
    }
}

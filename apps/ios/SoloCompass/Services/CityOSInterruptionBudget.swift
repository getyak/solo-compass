import Foundation

/// City OS v2 interruption budget (PRD §4.3): all *proactive* City-OS surfaces
/// combined — the one-time kit auto-surface and the compliance banner's first
/// appearance of a day — may fire at most twice per local day. This is the
/// quantified form of the "不做 engagement loop" anti-goal.
///
/// Same UserDefaults day-ring pattern as `LiveActivityService.consumeDailyBudget`
/// and `ProactiveNudgeScheduler.budgetKey`; the dailyOmen Live Activity keeps
/// its own separate 1/day budget and is intentionally NOT counted here.
public enum CityOSInterruptionBudget {
    /// Maximum proactive City-OS surfacings per local day.
    public static let maxProactivePerDay = 2

    /// Attempts to consume one unit of today's budget. Returns false (and
    /// consumes nothing) when the budget is exhausted — callers must then
    /// stay silent.
    @discardableResult
    public static func consumeProactive(now: Date = Date(), calendar: Calendar = .current, defaults: UserDefaults = .standard) -> Bool {
        let key = budgetKey(for: now, calendar: calendar)
        let used = defaults.integer(forKey: key)
        guard used < maxProactivePerDay else { return false }
        defaults.set(used + 1, forKey: key)
        return true
    }

    /// How many proactive surfacings remain today (0...maxProactivePerDay).
    public static func remainingToday(now: Date = Date(), calendar: Calendar = .current, defaults: UserDefaults = .standard) -> Int {
        max(0, maxProactivePerDay - defaults.integer(forKey: budgetKey(for: now, calendar: calendar)))
    }

    /// UserDefaults key for the given local day, e.g.
    /// `com.solocompass.cityos.proactive.2026-07-06.v1`.
    static func budgetKey(for date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "com.solocompass.cityos.proactive.%04d-%02d-%02d.v1",
            comps.year ?? 0, comps.month ?? 0, comps.day ?? 0
        )
    }
}

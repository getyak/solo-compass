import Foundation

/// Hour-of-day proximity signal: how close is `date` to the experience's
/// `bestStartHour`?
///
/// - No `bestTimes` (and thus no `bestStartHour`) → `0.5` (neutral).
/// - Inside any open `bestTimes` window → `1.0` (plateau): once you are within
///   a recommended window the hour itself is already ideal, so this signal must
///   not drag the composite below the timing signal's `1.0`.
/// - Otherwise a Gaussian decay centered on `bestStartHour`, using the circular
///   (wrap-around-midnight) distance in minutes, with `sigma = 90min`.
public struct HourOfDaySignal: NowSignal {
    public static let key = "hourOfDay"
    /// **Relative** weight — see `BestTimesSignal.weight` for the
    /// normalization story. 0.2 means "half as decisive as bestTimes" in
    /// today's two-signal stack; the absolute number is meaningless on its
    /// own and only takes effect after `composeNowScore` divides by the
    /// total weight of all signals that contributed.
    public static let weight = 0.2

    /// Full width of the Gaussian, in minutes.
    static let sigmaMinutes = 90.0

    public init() {}

    public func score(for experience: Experience, at date: Date) async -> NowSignalContribution {
        evaluate(for: experience, at: date)
    }

    /// Synchronous core, also used by `Experience.nowScore(at:)`'s sync path.
    func evaluate(for experience: Experience, at date: Date) -> NowSignalContribution {
        guard let bestStartHour = experience.bestStartHour else {
            return NowSignalContribution(value: 0.5, weight: Self.weight, reason: "no bestStartHour")
        }
        // Inside an open window the hour is already ideal — plateau at 1.0.
        if BestTimesSignal.isOpen(experience.bestTimes, at: date) {
            return NowSignalContribution(value: 1.0, weight: Self.weight, reason: "at ideal hour")
        }
        let cal = Calendar.current
        let nowMinutes = Double(cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date))
        let centerMinutes = Double(bestStartHour * 60)
        let delta = HourOfDaySignal.circularMinuteDistance(nowMinutes, centerMinutes)
        let sigma = Self.sigmaMinutes
        let value = exp(-(delta * delta) / (2.0 * sigma * sigma))
        return NowSignalContribution(
            value: value,
            weight: Self.weight,
            reason: "near ideal hour"
        )
    }

    /// Shortest distance in minutes between two wall-clock times on a 24h circle.
    static func circularMinuteDistance(_ a: Double, _ b: Double) -> Double {
        let dayMinutes = 24.0 * 60.0
        let raw = abs(a - b).truncatingRemainder(dividingBy: dayMinutes)
        return min(raw, dayMinutes - raw)
    }
}

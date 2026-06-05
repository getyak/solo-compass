import Foundation
import CoreLocation

/// Weather provider seam so `WeatherSignal` can be unit-tested against a mock
/// without standing up SwiftData / the network. `WeatherService` conforms to it
/// (see the extension below), so production callers inject the real service.
@MainActor
public protocol CurrentWeatherProviding {
    /// Current weather for `coord`, or `nil` when none is available (offline
    /// cache miss, no key, decode failure). `WeatherSignal` treats any failure
    /// as "no weather" and degrades to a neutral, zero-weight contribution.
    func snapshot(at coord: CLLocationCoordinate2D) async -> WeatherSnapshot?
}

/// `WeatherService` adapter: collapse the throwing `current(at:)` into the
/// optional shape `WeatherSignal` wants. Every `WeatherError` (offline, no key,
/// decode) maps to `nil` so the signal never crashes the composite.
extension WeatherService: CurrentWeatherProviding {
    public func snapshot(at coord: CLLocationCoordinate2D) async -> WeatherSnapshot? {
        try? await current(at: coord)
    }
}

/// Weather signal: downgrade *outdoor* experiences when the sky is bad, leave
/// *indoor* ones untouched.
///
/// Outdoor = `.nature`, or `.nightlife` only when the experience is tagged
/// `rooftop`. Everything else (`.coffee`, `.work`, `.wellness`, `.culture`,
/// `.food`, plain `.nightlife`, `.hidden`) is treated as indoor and returns a
/// full-strength, no-reason contribution so weather never bleeds into venues it
/// can't affect.
///
/// Outdoor scoring ladder (worst wins):
///   - clear / partlyCloudy            → 1.0
///   - cloudy & precipChance < 30%     → 0.9
///   - rain (precipChance ≥ 30%)       → 0.5
///   - storm, wind ≥ 30 km/h, or
///     precipChance ≥ 70%              → 0.0
///
/// Offline / no snapshot → neutral `(0.5, weight 0, nil)`: it drops out of the
/// weighted average so a cache miss can't tilt the score either way.
@MainActor
public struct WeatherSignal: NowSignal {
    public static let key = "weather"
    public static let weight = 0.15

    /// Wind speed (km/h) at or above which any outdoor venue is a hard no.
    static let stormWindKph: Double = 30
    /// Precip chance (%) that flips a venue from "rain" to "storm-grade".
    static let stormPrecipPct: Int = 70
    /// Precip chance (%) at/above which cloudy weather counts as rain.
    static let rainPrecipPct: Int = 30

    private let weather: CurrentWeatherProviding

    /// - Parameter weather: weather provider (the live `WeatherService` in
    ///   production; a mock in tests). Injected so the signal is unit-testable.
    public init(weather: CurrentWeatherProviding) {
        self.weather = weather
    }

    public func score(for experience: Experience, at date: Date) async -> NowSignalContribution {
        // Indoor venues ignore weather entirely — full strength, no reason.
        guard Self.isOutdoor(experience) else {
            return NowSignalContribution(value: 1.0, weight: Self.weight, reason: nil)
        }

        // Outdoor but we can't place it / have no snapshot → neutral, drop out.
        guard let coord = experience.coordinate,
              let snapshot = await weather.snapshot(at: coord) else {
            return NowSignalContribution(value: 0.5, weight: 0.0, reason: nil)
        }

        let value = Self.outdoorValue(for: snapshot)
        return NowSignalContribution(
            value: value,
            weight: Self.weight,
            reason: Self.reason(for: snapshot)
        )
    }

    // MARK: - Classification

    /// Outdoor = nature, or rooftop-tagged nightlife. Everything else is indoor.
    static func isOutdoor(_ experience: Experience) -> Bool {
        switch experience.category {
        case .nature:
            return true
        case .nightlife:
            return (experience.userTags ?? []).contains { $0.caseInsensitiveCompare("rooftop") == .orderedSame }
        default:
            return false
        }
    }

    // MARK: - Scoring

    /// Map a snapshot to an outdoor value. "Worst wins": a storm-grade reading
    /// short-circuits to `0.0` regardless of the nominal condition bucket.
    static func outdoorValue(for s: WeatherSnapshot) -> Double {
        if isStormGrade(s) { return 0.0 }
        switch s.condition {
        case .clear, .partlyCloudy:
            return 1.0
        case .cloudy, .fog:
            return s.precipChancePct >= rainPrecipPct ? 0.5 : 0.9
        case .rain, .snow:
            return 0.5
        case .storm:
            return 0.0
        }
    }

    /// Hard-no conditions: an explicit storm, dangerous wind, or near-certain
    /// precipitation. Any one of these forces the outdoor value to `0.0`.
    static func isStormGrade(_ s: WeatherSnapshot) -> Bool {
        s.condition == .storm
            || s.windKph >= stormWindKph
            || s.precipChancePct >= stormPrecipPct
    }

    // MARK: - Reason

    /// Localized, human-readable reason, e.g. `晴 · 27°C · 适合` or
    /// `雷雨预警 · 不建议外出`. Temperature is rounded to whole degrees.
    static func reason(for s: WeatherSnapshot) -> String {
        let temp = Int(s.tempC.rounded())
        if isStormGrade(s) {
            return NSLocalizedString("nowscore.weather.storm", comment: "Storm — outdoor not advised")
        }
        let format: String
        switch s.condition {
        case .clear, .partlyCloudy:
            format = NSLocalizedString("nowscore.weather.sunny", comment: "Clear weather, suits outdoor")
        case .rain, .snow:
            format = NSLocalizedString("nowscore.weather.rain", comment: "Rain — outdoor discouraged")
        case .cloudy, .fog:
            format = s.precipChancePct >= rainPrecipPct
                ? NSLocalizedString("nowscore.weather.rain", comment: "Rain — outdoor discouraged")
                : NSLocalizedString("nowscore.weather.cloudy", comment: "Cloudy weather")
        case .storm:
            // Unreachable: storm is caught by isStormGrade above. Defensive.
            return NSLocalizedString("nowscore.weather.storm", comment: "Storm — outdoor not advised")
        }
        return String(format: format, temp)
    }
}

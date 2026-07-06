import Foundation
import Observation

/// City OS v2 root-state store (PRD §4.1): the traveler's per-city mode
/// (Live / Plan / Recall) plus the once-per-city kit auto-surface bookkeeping.
///
/// Deliberately NOT part of `MapViewModel` (already a 3k-line camera/POI
/// object) — this is relationship state, not map state. Raw persistence lives
/// in the `UserPreferences` blob (`cityModesRaw` / `kitSeenCities`); this
/// store owns the semantics.
@MainActor
@Observable
public final class CityOSStore {
    private let preferences: UserPreferences

    /// Creates the store over the given preferences blob.
    public init(preferences: UserPreferences) {
        self.preferences = preferences
    }

    /// Canonical storage key for a city code: trimmed + lowercased, matching
    /// the DB's lowercase convention (iOS surfaces use uppercase "VTE").
    public static func normalizedCityKey(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The mode for a city; unknown/nil cities default to `.live` — mode is
    /// an enhancement, never a gate that hides content.
    public func mode(for cityCode: String?) -> CityMode {
        guard let cityCode, !cityCode.isEmpty else { return .live }
        let key = Self.normalizedCityKey(cityCode)
        guard let raw = preferences.cityModesRaw[key], let mode = CityMode(rawValue: raw) else {
            return .live
        }
        return mode
    }

    /// Sets the mode for a city (persists via the preferences blob).
    public func setMode(_ mode: CityMode, for cityCode: String) {
        let key = Self.normalizedCityKey(cityCode)
        var raw = preferences.cityModesRaw
        raw[key] = mode.rawValue
        preferences.cityModesRaw = raw
    }

    /// Whether the landing kit has already auto-surfaced for this city.
    public func hasSeenKit(_ cityCode: String) -> Bool {
        preferences.kitSeenCities.contains(Self.normalizedCityKey(cityCode))
    }

    /// Records that the landing kit auto-surfaced once for this city — it
    /// never pushes itself again (PRD §4.3); the drawer tab remains the way
    /// back in.
    public func markKitSeen(_ cityCode: String) {
        var seen = preferences.kitSeenCities
        seen.insert(Self.normalizedCityKey(cityCode))
        preferences.kitSeenCities = seen
    }
}

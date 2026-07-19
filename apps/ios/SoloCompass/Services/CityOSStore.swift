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

    /// Infer the city's mode from signals the app already has, so the traveler
    /// never has to flip it by hand: a stay that has ended (stage `.leave`) →
    /// recall; a GPS fix inside the city → live; a city picked far from where we
    /// are (no fix nearby) → plan.
    ///
    /// - Parameters:
    ///   - cityCode: the city being framed (currently only used for symmetry
    ///     with the other store APIs; the decision is driven by the signals).
    ///   - isUserInCity: whether a GPS fix places the traveler inside this city
    ///     (computed by the caller from distance to the city center).
    ///   - stage: the lifecycle stage from `stage(for:daysStayed:)`; `.leave`
    ///     means the stay has ended.
    ///
    /// Pure so it can be unit-tested without a live location or preferences.
    public func inferMode(for cityCode: String?, isUserInCity: Bool, stage: CityStage?) -> CityMode {
        // A finished stay reads as recall regardless of where the phone is now.
        if stage == .leave { return .recall }
        // Standing in the city → live; a far-away pick with no nearby fix → plan.
        return isUserInCity ? .live : .plan
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

    // MARK: - Plan mode · pre-trip checklist (City OS v3)

    /// Whether a kit item is ticked on this city's pre-trip checklist.
    public func isKitTodoDone(_ kind: CityKitItem.Kind, cityCode: String) -> Bool {
        preferences.kitTodosDoneRaw[Self.normalizedCityKey(cityCode)]?
            .contains(kind.rawValue) ?? false
    }

    /// Toggles a pre-trip checklist tick (persists via the preferences blob).
    public func toggleKitTodo(_ kind: CityKitItem.Kind, cityCode: String) {
        let key = Self.normalizedCityKey(cityCode)
        var all = preferences.kitTodosDoneRaw
        var done = Set(all[key] ?? [])
        if done.contains(kind.rawValue) {
            done.remove(kind.rawValue)
        } else {
            done.insert(kind.rawValue)
        }
        // Sorted for a stable blob — Set order would churn the persisted JSON.
        all[key] = done.sorted()
        preferences.kitTodosDoneRaw = all
    }

    /// How many of the given kit's items are ticked for this city. Counts only
    /// kinds present in `kit`, so stale ticks from a changed kit don't inflate
    /// the Plan card's progress.
    public func kitTodoDoneCount(cityCode: String, kit: [CityKitItem]) -> Int {
        kit.filter { isKitTodoDone($0.kind, cityCode: cityCode) }.count
    }

    // MARK: - Recall mode · 印证 (City OS v3)

    /// Whether the traveler has personally verified this experience.
    public func isVerified(_ experienceId: String) -> Bool {
        preferences.verifiedExperiences.contains(experienceId)
    }

    /// Records a personal verification — the Recall contribution loop's write
    /// path. Idempotent.
    public func markVerified(_ experienceId: String) {
        var verified = preferences.verifiedExperiences
        verified.insert(experienceId)
        preferences.verifiedExperiences = verified
    }

    // MARK: - Lifecycle stage (City OS v3)

    /// The lifecycle stage for a city: mode + days stayed → land/settle/live/
    /// leave (`CityStage.inferred`). Pass `ComplianceMath.daysStayed` for the
    /// current city, nil when no entry date is set.
    public func stage(for cityCode: String?, daysStayed: Int?) -> CityStage? {
        CityStage.inferred(mode: mode(for: cityCode), daysStayed: daysStayed)
    }
}

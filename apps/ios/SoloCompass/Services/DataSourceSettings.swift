import Foundation

// MARK: - DataSourceSettings
//
// Developer-tunable configuration for the explore POI pipeline. Two knobs the
// Developer Options panel exposes so testers can shape how nearby data is
// gathered without a rebuild:
//
//   1. **Which base sources compile in** — Amap (AutoNavi, mainland China),
//      OpenMap (OpenStreetMap via Overpass), or both. See `DataSourcePolicy`.
//   2. **How many POIs each base source pulls** per explore call — the
//      "surrounding data" fan-out width (`poiFetchLimit`).
//
// Everything is stored in `UserDefaults` under the `ds.*` namespace and read
// live by `EnrichmentAgent.basePOIs` (policy) and the service constructors in
// `MapViewModel` / `CompassMapView` (fetch limit). Absent keys resolve to the
// documented defaults, so a fresh install behaves exactly as before this
// feature landed.

/// Which base POI provider(s) participate in the explore pipeline.
///
/// The default (`both`) preserves the shipped region-routing behaviour: Amap is
/// authoritative inside mainland China (OSM is ~9× sparser there), Overpass
/// authoritative overseas, each falling back to the other. The single-source
/// modes let a tester pin the pipeline to exactly one provider — e.g. to A/B
/// the two data sources against each other in the same city, or to reproduce a
/// provider-specific bug in isolation.
public enum DataSourcePolicy: String, CaseIterable, Sendable, Identifiable {
    /// Region-routed: Amap in China, Overpass overseas, each a fallback for the
    /// other. This is the shipped behaviour and the default.
    case both
    /// Only ever query Amap. No Overpass fallback (MapKit skeletons still fold
    /// in). Outside China this typically yields little — that's the tester's
    /// explicit choice.
    case amapOnly
    /// Only ever query OpenMap/Overpass, even inside China. Amap is never hit.
    case openMapOnly

    public var id: String { rawValue }

    /// True when this policy permits querying Amap.
    public var allowsAmap: Bool { self != .openMapOnly }

    /// True when this policy permits querying OpenMap/Overpass.
    public var allowsOpenMap: Bool { self != .amapOnly }

    /// Localization key for the human-readable label shown in the picker.
    public var titleKey: String {
        switch self {
        case .both:        return "dev.dataSource.policy.both"
        case .amapOnly:    return "dev.dataSource.policy.amapOnly"
        case .openMapOnly: return "dev.dataSource.policy.openMapOnly"
        }
    }
}

/// A single base POI provider the Developer Options panel can probe / configure.
public enum DataSourceKind: String, CaseIterable, Sendable, Identifiable {
    case amap
    case openMap

    public var id: String { rawValue }

    /// Localization key for the provider's display name.
    public var titleKey: String {
        switch self {
        case .amap:    return "dev.dataSource.amap.name"
        case .openMap: return "dev.dataSource.openMap.name"
        }
    }

    /// Whether the current policy currently keeps this provider in the pipeline.
    public var isEnabledByPolicy: Bool {
        switch self {
        case .amap:    return DataSourceSettings.policy.allowsAmap
        case .openMap: return DataSourceSettings.policy.allowsOpenMap
        }
    }
}

/// UserDefaults-backed store for the explore data-source knobs. Static because
/// the values are process-global configuration read from many call sites
/// (`EnrichmentAgent`, `MapViewModel`, `CompassMapView`, the Developer Options
/// UI) — the same shape as `FeatureFlags`.
public enum DataSourceSettings {

    // MARK: Keys

    enum Keys {
        static let policy = "ds.policy"
        static let poiFetchLimit = "ds.poiFetchLimit"
    }

    // MARK: POI fetch limit

    /// Default number of POIs each base source pulls per explore call when the
    /// tester hasn't overridden it. Sits between the two historical per-service
    /// defaults (Overpass 30, Amap 75) and feeds the same ranking stage that
    /// keeps only the top handful, so a wider pool only improves ranking.
    public static let defaultPOIFetchLimit = 60

    /// Clamp bounds for the fetch limit. Below 10 an explore feels empty; above
    /// 120 the Amap pagination (25/page) and Overpass timeout stop paying off.
    public static let poiFetchLimitRange: ClosedRange<Int> = 10...120

    /// How many POIs each base source should fetch per explore call. Reads the
    /// override when set, otherwise `defaultPOIFetchLimit`. Always clamped to
    /// `poiFetchLimitRange`.
    public static var poiFetchLimit: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: Keys.poiFetchLimit)
            guard stored != 0 else { return defaultPOIFetchLimit }
            return min(max(stored, poiFetchLimitRange.lowerBound), poiFetchLimitRange.upperBound)
        }
        set {
            let clamped = min(max(newValue, poiFetchLimitRange.lowerBound), poiFetchLimitRange.upperBound)
            UserDefaults.standard.set(clamped, forKey: Keys.poiFetchLimit)
        }
    }

    // MARK: Policy

    /// Active data-source policy. Defaults to `.both` (shipped region routing)
    /// when no override is stored or the stored value is unrecognised.
    public static var policy: DataSourcePolicy {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Keys.policy),
                  let parsed = DataSourcePolicy(rawValue: raw) else {
                return .both
            }
            return parsed
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.policy)
        }
    }

    // MARK: Reset

    /// Remove every data-source override so policy + fetch limit revert to their
    /// documented defaults. Called from the Developer Options "Reset overrides"
    /// action alongside `FeatureFlags.clearAllOverrides()`.
    public static func reset() {
        UserDefaults.standard.removeObject(forKey: Keys.policy)
        UserDefaults.standard.removeObject(forKey: Keys.poiFetchLimit)
    }
}

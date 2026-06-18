import Foundation
import CoreLocation

// MARK: - POISource

/// Unified abstraction over the four POI providers — `OverpassService`,
/// `AmapPOIService`, `MapKitPOIService`, `FoursquareService` — so callers
/// (notably `MapViewModel` and `EnrichmentAgent`) can stop hard-binding to
/// concrete types.
///
/// Audit H3 / H4 identified the duplication: every implementation already
/// returns `POI` (= `OverpassService.POI` via the `Models/POI.swift`
/// typealias) and takes the same `(coordinate, radiusMeters, category)`
/// triple. Until this protocol existed the consumer had to know which
/// service produced which signal — a fan-out switch over four concrete
/// types in `enrichNearby`. With `POISource` the consumer can hold
/// `[any POISource]` and let the enrichment pipeline iterate sources.
///
/// Conforming types: see the dedicated `extension XYZ: POISource {}`
/// declarations on `OverpassService`, `AmapPOIService`, `MapKitPOIService`,
/// and `FoursquareService`. Each declares conformance only — no method body
/// changes — because the four `fetchPOIs(near:radiusMeters:category:)`
/// signatures already match this protocol exactly.
// Note: not `@MainActor`-bound. `OverpassService` is the one outlier among
// the four sources (audit M1) — it's `@Observable` but not main-isolated.
// Constraining this protocol to `@MainActor` would force a structural change
// to OverpassService just to introduce a name. Implementations remain free
// to declare main-actor isolation on the conformance site if they wish.
public protocol POISource: AnyObject {
    /// Provider-recognisable identifier used in logs / dedup keys.
    /// Defaults to the conforming type's name; override to disambiguate
    /// multiple instances of the same service.
    var sourceName: String { get }

    /// Fetch POIs within `radiusMeters` of `coordinate`. Implementations
    /// must be safe to call concurrently across distinct coordinates and
    /// must NOT throw on empty results — return `[]` so the merger can
    /// treat absence as "no signal" rather than "transient failure".
    func fetchPOIs(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        category: ExperienceCategory?
    ) async throws -> [POI]
}

public extension POISource {
    var sourceName: String { String(describing: type(of: self)) }
}

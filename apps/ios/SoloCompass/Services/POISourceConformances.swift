import Foundation
import CoreLocation

// MARK: - POISource conformances

// The four POI providers already publish a matching
// `fetchPOIs(near:radiusMeters:category:) async throws -> [POI]`
// surface; we just need to opt them into the shared protocol so
// downstream consumers can pass `[any POISource]`.
//
// Default-argument values declared on the concrete services
// (`radiusMeters: Int = 3000`, etc.) are preserved at the call site —
// protocol-witness dispatch does not strip them, and direct calls on the
// concrete type continue to use the original defaults.

extension OverpassService: POISource {
    public var sourceName: String { "overpass" }
}

extension AmapPOIService: POISource {
    public var sourceName: String { "amap" }
}

extension MapKitPOIService: POISource {
    public var sourceName: String { "mapkit" }
}

extension FoursquareService: POISource {
    public var sourceName: String { "foursquare" }
}

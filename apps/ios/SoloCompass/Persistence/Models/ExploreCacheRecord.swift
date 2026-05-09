import Foundation
import SwiftData

/// Cached Overpass POI batch keyed by region. Used by `OverpassService`
/// (Epic B US-B1) to skip re-fetching the same area within 14 days.
///
/// `regionKey` is a deterministic string like `"21.03_105.85_3000"` —
/// (lat rounded to 0.01°)_(lon rounded to 0.01°)_(radius meters). Rounding
/// at 0.01° (~1.1 km) means cache hits even after small map pans.
///
/// `osmJSON` is the raw Overpass JSON response so the cache survives any
/// changes to our `POI` decoder shape.
@Model
public final class ExploreCacheRecord {
    @Attribute(.unique) public var regionKey: String
    public var osmJSON: Data
    public var fetchedAt: Date
    public var poiCount: Int

    public init(regionKey: String, osmJSON: Data, fetchedAt: Date = Date(), poiCount: Int) {
        self.regionKey = regionKey
        self.osmJSON = osmJSON
        self.fetchedAt = fetchedAt
        self.poiCount = poiCount
    }
}

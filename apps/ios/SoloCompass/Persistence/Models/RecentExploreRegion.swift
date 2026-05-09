import Foundation
import SwiftData

/// One row per recent successful "Explore here". Used by US-A4 (offline
/// fallback) — when the user is offline, we look up the nearest recent
/// region and re-show the cached pins from SwiftData.
///
/// We keep only the last 3 (oldest evicted) so this table stays bounded.
@Model
public final class RecentExploreRegion {
    @Attribute(.unique) public var id: UUID
    public var centerLat: Double
    public var centerLon: Double
    public var radiusMeters: Int
    public var exploredAt: Date

    public init(
        id: UUID = UUID(),
        centerLat: Double,
        centerLon: Double,
        radiusMeters: Int,
        exploredAt: Date = Date()
    ) {
        self.id = id
        self.centerLat = centerLat
        self.centerLon = centerLon
        self.radiusMeters = radiusMeters
        self.exploredAt = exploredAt
    }
}

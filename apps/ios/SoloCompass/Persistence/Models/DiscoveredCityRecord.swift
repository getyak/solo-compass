import Foundation
import SwiftData

/// One row per city the user has reverse-geocoded after an Explore.
/// `cityCode` is a slug like `"vn-hanoi"` (Epic C US-C3). Used by the city
/// picker to show real names instead of the synthetic `osm_<lat>_<lon>`.
@Model
public final class DiscoveredCityRecord {
    @Attribute(.unique) public var cityCode: String
    public var name: String
    public var countryCode: String
    public var centerLat: Double
    public var centerLon: Double
    public var discoveredAt: Date

    public init(
        cityCode: String,
        name: String,
        countryCode: String,
        centerLat: Double,
        centerLon: Double,
        discoveredAt: Date = Date()
    ) {
        self.cityCode = cityCode
        self.name = name
        self.countryCode = countryCode
        self.centerLat = centerLat
        self.centerLon = centerLon
        self.discoveredAt = discoveredAt
    }
}

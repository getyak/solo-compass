import Foundation
import SwiftData

/// Cached city-brief content (落地包 kit rows + 在地 events) for one city,
/// keyed by lowercase city code. Used by `CityBriefService` so the kit and
/// events render instantly and stay offline-usable between refreshes.
///
/// Whole-payload JSON blobs (same idiom as `WeatherCacheRecord`): the cache
/// survives value-type shape changes, and there is no per-row mapping code to
/// drift. `fetchedAt` drives the service's refresh TTL.
@Model
public final class CityBriefCacheRecord {
    @Attribute(.unique) public var cityCode: String
    public var kitJSON: Data
    public var eventsJSON: Data
    public var fetchedAt: Date

    public init(cityCode: String, kitJSON: Data, eventsJSON: Data, fetchedAt: Date = Date()) {
        self.cityCode = cityCode
        self.kitJSON = kitJSON
        self.eventsJSON = eventsJSON
        self.fetchedAt = fetchedAt
    }
}

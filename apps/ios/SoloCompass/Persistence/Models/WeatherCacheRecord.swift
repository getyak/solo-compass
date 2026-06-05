import Foundation
import SwiftData

/// Cached current-weather snapshot keyed by a coarse coordinate cell. Used by
/// `WeatherService` (US-003) so NowScore can read weather for many markers
/// without one network call per pin.
///
/// `coordKey` is a deterministic string `"\(lat.rounded2)_\(lon.rounded2)"` —
/// latitude and longitude rounded to two decimals (~1.1 km cell). Rounding at
/// 0.01° means nearby markers share one cache row and one network fetch.
///
/// `snapshotJSON` is the JSON-encoded `WeatherSnapshot` so the cache survives
/// changes to the in-memory shape. `observedAt` drives the 12-hour TTL.
@Model
public final class WeatherCacheRecord {
    @Attribute(.unique) public var coordKey: String
    public var snapshotJSON: Data
    public var observedAt: Date

    public init(coordKey: String, snapshotJSON: Data, observedAt: Date = Date()) {
        self.coordKey = coordKey
        self.snapshotJSON = snapshotJSON
        self.observedAt = observedAt
    }
}

import Foundation
import SwiftData

/// One row per "user actually spent time at this experience." Multiple visits
/// to the same experience id are allowed (re-visits), so `experienceId` is
/// indexed but not unique — each visit gets its own row + timestamp so we can
/// drive month-by-month travel-archive aggregation, taste-profile updates,
/// and the time-capsule "1 year later" geofence trigger.
///
/// Privacy contract: coordinates are stored as a `Data` blob of two `Double`s
/// in `[longitude, latitude]` order (matches the codebase-wide GeoJSON
/// convention). The blob lives on-device only; no cloud sync. The dwell
/// counter is in seconds because most visits last 5-180 minutes — `Int`
/// stays well within range and avoids the rounding error of `TimeInterval`.
///
/// Created by VisitTrackingService (planned: P1.1 #110) when a user enters a
/// 200m CLCircularRegion around an experience and stays ≥5 minutes. The 5min
/// minimum filters out drive-bys and walk-throughs; tweakable via the
/// service's `minimumDwell` constant if the threshold proves wrong in beta.
@Model
public final class VisitRecord {
    @Attribute(.unique) public var id: UUID
    public var experienceId: String
    public var visitedAt: Date
    public var dwellSeconds: Int
    /// Optional weather code at the time of visit (e.g. "clear", "rain"),
    /// snapped at write-time so the archive can later read "you sat here in
    /// the rain" without re-querying WeatherService. Optional because weather
    /// fetch may be offline / rate-limited; missing data is acceptable.
    public var weatherCode: String?
    /// Two-double blob in `[lon, lat]` order — matches GeoJSON / Mapbox /
    /// PostGIS, NOT Google's `[lat, lng]`. Decode via `coords` accessor.
    public var coordSnapBlob: Data?

    public init(
        id: UUID = UUID(),
        experienceId: String,
        visitedAt: Date = Date(),
        dwellSeconds: Int,
        weatherCode: String? = nil,
        coordSnapBlob: Data? = nil
    ) {
        self.id = id
        self.experienceId = experienceId
        self.visitedAt = visitedAt
        self.dwellSeconds = dwellSeconds
        self.weatherCode = weatherCode
        self.coordSnapBlob = coordSnapBlob
    }

    /// Encode `[lon, lat]` coordinates into the storage blob. Returns `nil`
    /// blob if coords is empty/wrong-shape so callers can't accidentally
    /// persist a malformed two-Double payload.
    public static func encodeCoords(_ coords: [Double]?) -> Data? {
        guard let coords, coords.count == 2 else { return nil }
        return coords.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Decode the storage blob back to `[lon, lat]`. Returns `nil` if the
    /// blob is missing or the wrong byte length, so a corrupt row surfaces
    /// as "no location" rather than crashing on a forced cast.
    public var coords: [Double]? {
        guard let coordSnapBlob,
              coordSnapBlob.count == MemoryLayout<Double>.size * 2 else { return nil }
        return coordSnapBlob.withUnsafeBytes { raw -> [Double] in
            let buffer = raw.bindMemory(to: Double.self)
            return Array(buffer)
        }
    }
}

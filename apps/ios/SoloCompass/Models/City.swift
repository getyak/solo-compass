/// Canonical city record mirroring packages/core/src/city.ts.
/// geonameId is the stable deduplication key across language variants.
public struct City: Codable, Identifiable, Hashable {
    /// GeoNames unique identifier. Stable across language variants.
    public let geonameId: Int
    /// Name in the local/native script of the country.
    public let nameLocal: String
    /// Name in the system/display language (romanized or English).
    public let nameSystem: String
    /// WGS-84 latitude.
    public let lat: Double
    /// WGS-84 longitude.
    public let lon: Double
    /// ISO 3166-1 alpha-2 country code, e.g. "TH", "LA", "VN".
    public let countryCode: String

    public var id: Int { geonameId }

    public init(
        geonameId: Int,
        nameLocal: String,
        nameSystem: String,
        lat: Double,
        lon: Double,
        countryCode: String
    ) {
        self.geonameId = geonameId
        self.nameLocal = nameLocal
        self.nameSystem = nameSystem
        self.lat = lat
        self.lon = lon
        self.countryCode = countryCode
    }
}

// MARK: - Dedupe

extension Array where Element == City {
    /// Returns a new array with duplicates by geonameId removed.
    /// First occurrence wins.
    public func deduplicatedByGeonameId() -> [City] {
        var seen = Set<Int>()
        return filter { seen.insert($0.geonameId).inserted }
    }
}

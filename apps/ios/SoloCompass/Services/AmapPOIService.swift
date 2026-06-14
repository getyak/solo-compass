import Foundation
import CoreLocation
import Observation
import os

/// Mainland-China POI source backed by Amap (AutoNavi) "Search POI 2.0 — Around
/// Search" (`/v5/place/around`). Used by the explore pipeline only for
/// coordinates inside mainland China, where OpenStreetMap/Overpass coverage is
/// an order of magnitude thinner than reality (Shenzhen CBD: ~260 OSM POIs vs
/// ~2244 in Chiang Mai's old town for the same 3 km query). Amap mirrors the
/// real density.
///
/// Shape parity: returns `OverpassService.POI` — the canonical POI type across
/// every source — so results flow through the same `FoursquareService.enrichMerge`
/// dedupe path as Overpass / MapKit / Foursquare with zero downstream changes.
///
/// ## Two non-negotiable boundaries live here
///
/// 1. **Coordinate system.** Amap speaks GCJ-02 in and out; the app speaks
///    WGS84. We convert the query center WGS84 → GCJ-02 before the request and
///    every returned point GCJ-02 → WGS84 before handing it back, via
///    `CoordinateConverter`. Callers only ever see WGS84.
///
/// 2. **No persistence (Amap ToS §3.5 / §4.12.2).** Amap forbids storing or
///    caching its raw data or building a derivative database. So this service
///    caches **in memory only** (`NSCache`, cleared on process exit) and never
///    touches SwiftData. The explore pipeline must skip its geohash disk cache
///    on the China branch (see `EnrichmentAgent`). What *may* be persisted is
///    SoloCompass's own AI-synthesized `Experience` (its own content) — not
///    Amap's raw fields.
///
/// Best-effort by design: an empty result or a quota/error response returns
/// `[]` rather than throwing, so the merge step degrades to whatever other
/// sources returned. A truly absent key throws `missingKey` so the caller can
/// fall back to the overseas (Overpass) branch.
@MainActor
@Observable
public final class AmapPOIService {
    public enum AmapError: Error, LocalizedError {
        case missingKey
        case requestFailed(status: Int)
        case apiError(code: String, info: String)

        public var errorDescription: String? {
            switch self {
            case .missingKey:
                return NSLocalizedString("amap.error.missingKey", comment: "Amap API key not configured")
            case .requestFailed(let status):
                return String(format: NSLocalizedString("amap.error.request", comment: "Amap request failed status %d"), status)
            case .apiError(let code, let info):
                return String(format: NSLocalizedString("amap.error.api", comment: "Amap API error %@ %@"), code, info)
            }
        }
    }

    public private(set) var isFetching: Bool = false

    private let session: URLSession
    private let maxResults: Int
    private let keyProvider: () -> String

    private static let logger = Logger(subsystem: "com.daypage.solocompass", category: "AmapPOIService")

    /// Session-only cache. Key: rounded center + radius + category. Holds the
    /// already-converted (WGS84) POIs so a repeated explore of the same cell in
    /// one session avoids a second Amap call — without ever hitting disk.
    private let memoryCache = NSCache<NSString, CachedPOIs>()

    final class CachedPOIs {
        let pois: [OverpassService.POI]
        init(_ pois: [OverpassService.POI]) { self.pois = pois }
    }

    /// `keyProvider` is injected so tests can supply an empty or fake key
    /// without touching `Secrets`. A `nil` default resolves to
    /// `Secrets.resolvedAmapKey` in production — the fallback lives in the init
    /// body (not the default argument) because `Secrets` is `internal` and a
    /// `public` default argument may not reference internal symbols.
    public init(
        session: URLSession = .shared,
        maxResults: Int = 25,
        keyProvider: (() -> String)? = nil
    ) {
        self.session = session
        self.maxResults = maxResults
        self.keyProvider = keyProvider ?? { Secrets.resolvedAmapKey }
    }

    // MARK: - Public

    /// Fetch up to `maxResults` POIs within `radiusMeters` of `coordinate`
    /// (WGS84). Returns WGS84 POIs. Mirrors
    /// `OverpassService.fetchPOIs(near:radiusMeters:category:)` so it slots into
    /// the same pipeline.
    public func fetchPOIs(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Int = 3000,
        category: ExperienceCategory? = nil
    ) async throws -> [OverpassService.POI] {
        let key = keyProvider()
        guard !key.isEmpty else { throw AmapError.missingKey }

        let cacheKey = Self.cacheKey(coordinate: coordinate, radiusMeters: radiusMeters, category: category)
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached.pois
        }

        // Convert the query center WGS84 → GCJ-02 for Amap. `location` is
        // "lon,lat" with 6 decimals per the Amap spec.
        let gcj = CoordinateConverter.wgs84ToGcj02(coordinate)
        guard let url = Self.buildURL(
            key: key,
            gcjCenter: gcj,
            radiusMeters: radiusMeters,
            category: category,
            pageSize: maxResults
        ) else {
            throw AmapError.requestFailed(status: -1)
        }

        isFetching = true
        defer { isFetching = false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("SoloCompass-iOS/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AmapError.requestFailed(status: status)
        }

        let decoded = try JSONDecoder().decode(AroundResponse.self, from: data)
        // status "1" = success. Anything else (quota, invalid key, no result)
        // degrades to empty so the merge step still proceeds with other sources.
        // Log the `info` field (e.g. "DAILY_QUERY_OVER_LIMIT", "INVALID_USER_KEY")
        // so a quota/auth failure is observable instead of silently looking like
        // "no POIs here" — the operator needs to see why China quality dropped.
        guard decoded.status == "1" else {
            Self.logger.info("Amap non-success status=\(decoded.status, privacy: .public) info=\(decoded.info ?? "nil", privacy: .public)")
            return []
        }

        let pois = (decoded.pois ?? []).compactMap { Self.poi(from: $0) }
        memoryCache.setObject(CachedPOIs(pois), forKey: cacheKey)
        return pois
    }

    // MARK: - URL building

    static func buildURL(
        key: String,
        gcjCenter: CLLocationCoordinate2D,
        radiusMeters: Int,
        category: ExperienceCategory?,
        pageSize: Int
    ) -> URL? {
        var comps = URLComponents(string: "https://restapi.amap.com/v5/place/around")
        // Amap caps radius at 50 km and page_size at 25.
        let radius = min(max(radiusMeters, 1), 50_000)
        let size = min(max(pageSize, 1), 25)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "location", value: String(format: "%.6f,%.6f", gcjCenter.longitude, gcjCenter.latitude)),
            URLQueryItem(name: "radius", value: String(radius)),
            URLQueryItem(name: "page_size", value: String(size)),
            URLQueryItem(name: "page_num", value: "1"),
            // Sort by distance so the closest, most relevant POIs survive the cap.
            URLQueryItem(name: "sortrule", value: "distance"),
            // Ask for the richer field set (business hours, rating, etc.) so
            // synthesis can cite real signals.
            URLQueryItem(name: "show_fields", value: "business,indoor")
        ]
        if let types = category.flatMap(amapTypes(for:)) {
            items.append(URLQueryItem(name: "types", value: types))
        }
        comps?.queryItems = items
        return comps?.url
    }

    /// Map an `ExperienceCategory` to Amap POI typecodes (pipe-separated). Codes
    /// are the published Amap classification: 05=餐饮, 0505=咖啡厅, 11=风景名胜,
    /// 08=体育休闲, 06=购物, 14=科教文化(museums/galleries). nil → no `types`
    /// filter, i.e. a broad nearby search.
    static func amapTypes(for category: ExperienceCategory) -> String? {
        switch category {
        case .coffee:    return "050500"          // 咖啡厅
        case .food:      return "050000"          // 餐饮服务 (all dining)
        case .nightlife: return "080300|050118"   // 娱乐场所 | 酒吧
        case .work:      return "140600|060000"   // 图书馆 | 商场(coworking-ish)
        case .culture:   return "140000|110000"   // 科教文化 | 风景名胜(museums + sights)
        case .nature:    return "110100|110200"   // 公园广场 | 风景名胜
        case .wellness:  return "080100|090000"   // 运动场馆 | 医疗保健(spa/wellness)
        case .hidden:    return nil               // broad search; let ranking surface gems
        }
    }

    // MARK: - Mapping

    /// Convert an Amap POI into an `OverpassService.POI`, converting its GCJ-02
    /// coordinate back to WGS84. Returns nil when name or coordinate is missing
    /// or unparseable.
    static func poi(from amap: AmapPOI) -> OverpassService.POI? {
        guard let name = amap.name, !name.isEmpty else { return nil }
        // Amap `location` is "lon,lat" in GCJ-02.
        guard let location = amap.location,
              let gcj = parseLocation(location) else { return nil }
        let wgs = CoordinateConverter.gcj02ToWgs84(gcj)

        // Compliance (Amap ToS §3.5 / §4.12.2, ADR §3.2): we must NOT persist or
        // redistribute Amap's raw structured fields. The downstream Experience is
        // persisted to SwiftData, so anything placed in `tags` here can end up on
        // disk. We therefore project ONLY the minimum needed to synthesize and
        // classify — the place name (with a `© AutoNavi` source marker) and a
        // category bucket derived from the typecode. The raw address, phone,
        // opening hours, and rating are deliberately dropped: they are Amap's
        // distributable data, not SoloCompass's own synthesized content.
        var tags: [String: String] = ["name": name, "source": "amap"]
        // Map the Amap typecode prefix to an OSM-style tag so
        // `OverpassService.category(for:)` keeps resolving buckets unchanged.
        // A typecode-derived bucket is a category, not raw redistributable data.
        if let typecode = amap.typecode, let osm = osmTag(forTypecode: typecode) {
            tags[osm.key] = osm.value
        }

        return OverpassService.POI(
            osmId: stableInt64Id(amapId: amap.id, name: name, coordinate: wgs),
            name: name,
            nameEn: nil,
            lat: wgs.latitude,
            lon: wgs.longitude,
            tags: tags
        )
    }

    /// Parse Amap "lon,lat" string into a coordinate (still GCJ-02).
    static func parseLocation(_ s: String) -> CLLocationCoordinate2D? {
        let parts = s.split(separator: ",")
        guard parts.count == 2,
              let lon = Double(parts[0]),
              let lat = Double(parts[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Map an Amap typecode (6-digit, hierarchical) to an OSM-style (key,value)
    /// using its leading digits — matching how MapKit maps Apple categories.
    static func osmTag(forTypecode code: String) -> (key: String, value: String)? {
        let p2 = String(code.prefix(2))
        let p4 = String(code.prefix(4))
        switch true {
        case p4 == "0505":   return ("amenity", "cafe")         // 咖啡厅
        case code == "050118": return ("amenity", "bar")        // 酒吧 — before the 05 wildcard
        case p2 == "05":     return ("amenity", "restaurant")   // 餐饮服务
        case p4 == "0803":   return ("amenity", "bar")          // 娱乐场所 → bar-ish
        case p2 == "11":   return ("tourism", "attraction")     // 风景名胜
        case p2 == "14":   return ("tourism", "museum")         // 科教文化
        case p2 == "08":   return ("leisure", "fitness_centre") // 体育休闲
        case p2 == "09":   return ("amenity", "spa")            // 医疗保健 → wellness
        case p2 == "06":   return ("shop", "mall")              // 购物
        default:           return nil
        }
    }

    /// Stable `Int64` id from Amap's own POI id (a hex-ish string). Falls back
    /// to hashing name+coordinate. High marker bit `0x1000…` is distinct from
    /// OSM (low range), MapKit (`0x2000…`), and Foursquare (`0x4000…`) so Amap
    /// ids never collide with the other sources in the merge.
    static func stableInt64Id(amapId: String?, name: String, coordinate: CLLocationCoordinate2D) -> Int64 {
        let rLat = (coordinate.latitude * 10_000).rounded() / 10_000
        let rLon = (coordinate.longitude * 10_000).rounded() / 10_000
        let seed = amapId.map { "amap:\($0)" } ?? "\(name)|\(rLat)|\(rLon)"
        var hash: UInt64 = 1469598103934665603 // FNV offset basis
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211 // FNV prime
        }
        let positive = hash & 0x7FFF_FFFF_FFFF_FFFF
        return Int64(bitPattern: positive | 0x1000_0000_0000_0000)
    }

    private static func cacheKey(
        coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        category: ExperienceCategory?
    ) -> NSString {
        // 4-decimal (~11 m) rounding so near-identical centers share a cell.
        let lat = (coordinate.latitude * 10_000).rounded() / 10_000
        let lon = (coordinate.longitude * 10_000).rounded() / 10_000
        let cat = category?.rawValue ?? "all"
        return "\(lat),\(lon)_r\(radiusMeters)_\(cat)" as NSString
    }

    // MARK: - Decodable shapes (Amap /v5/place/around)

    struct AroundResponse: Decodable {
        let status: String
        let info: String?
        let pois: [AmapPOI]?
    }

    struct AmapPOI: Decodable {
        let id: String?
        let name: String?
        let location: String?
        let typecode: String?
        let address: String?
        let tel: String?
        let business: Business?

        struct Business: Decodable {
            let opentimeToday: String?
            let rating: String?

            enum CodingKeys: String, CodingKey {
                case opentimeToday = "opentime_today"
                case rating
            }
        }
    }
}

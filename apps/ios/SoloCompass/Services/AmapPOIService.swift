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

    /// In-flight request dedup. progressiveRadii fan-out + user re-taps can
    /// kick off the same (coordinate, radius, category) request concurrently;
    /// without this, each tap burns one of the 5000/month quota slots. Keyed
    /// by the same cacheKey scheme; cleared in the task continuation.
    /// Single-threaded access guaranteed by @MainActor.
    private var inFlight: [NSString: Task<[OverpassService.POI], Error>] = [:]

    /// progressiveRadii history: per (center, category), the largest radius
    /// we've successfully fetched. A subsequent fetch at a smaller radius can
    /// filter that result locally instead of re-querying amap — the 5k → 10k
    /// → 25k → 100k progressive ring previously burnt 4x quota per explore.
    /// Center keyed at the same 4-decimal precision as cacheKey.
    private var largestFetchedRadius: [NSString: Int] = [:]

    /// Transient (non-persisted) enrichment fields per POI id — the amap raw
    /// signals (rating / opening hours / phone / address) that ADR §3.2
    /// forbids writing to SwiftData but ARE allowed as ephemeral inputs to
    /// the AI synthesis prompt. The pipeline reads these between fetchPOIs
    /// returning and AIService consuming, then discards. NEVER serialize.
    /// Keyed by `OverpassService.POI.osmId` (the stable Amap-marked id).
    public struct TransientAmapEnrichment {
        public let rating: String?
        public let opentimeToday: String?
        public let phone: String?
        public let address: String?
    }
    public private(set) var transientEnrichments: [Int64: TransientAmapEnrichment] = [:]

    /// Pop enrichments for the POI ids the caller is about to synthesize, so
    /// the cache doesn't accumulate cross-session data. Reads + removes.
    public func consumeEnrichments(for ids: [Int64]) -> [Int64: TransientAmapEnrichment] {
        var out: [Int64: TransientAmapEnrichment] = [:]
        for id in ids {
            if let e = transientEnrichments.removeValue(forKey: id) {
                out[id] = e
            }
        }
        return out
    }

    /// `keyProvider` is injected so tests can supply an empty or fake key
    /// without touching `Secrets`. A `nil` default resolves to
    /// `Secrets.resolvedAmapKey` in production — the fallback lives in the init
    /// body (not the default argument) because `Secrets` is `internal` and a
    /// `public` default argument may not reference internal symbols.
    public init(
        session: URLSession = .shared,
        maxResults: Int = 75,
        keyProvider: (() -> String)? = nil
    ) {
        self.session = session
        self.maxResults = maxResults
        self.keyProvider = keyProvider ?? { Secrets.resolvedAmapKey }
        // Bound the session cache: progressiveRadii (4 rings) × N coordinates
        // × M categories can grow unbounded over a long session. 200 cells covers
        // typical exploration; NSCache evicts LRU under memory pressure regardless.
        memoryCache.countLimit = 200
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
        // DIAG: amap key presence on device build — "did .env reach the binary"
        Self.logger.info("🔑 amap key len=\(key.count, privacy: .public) empty=\(key.isEmpty, privacy: .public)")
        guard !key.isEmpty else { throw AmapError.missingKey }

        let cacheKey = Self.cacheKey(coordinate: coordinate, radiusMeters: radiusMeters, category: category)
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached.pois
        }

        // Reuse a strictly larger same-(center, category) fetch by filtering
        // locally on great-circle distance. Saves a network round-trip across
        // the progressiveRadii ladder (5k → 10k → 25k → 100k previously burned
        // 4 separate amap queries; now only the outermost cache-miss hits).
        let centerKey = Self.centerCacheKey(coordinate: coordinate, category: category)
        if let largest = largestFetchedRadius[centerKey], largest > radiusMeters {
            let largestKey = Self.cacheKey(coordinate: coordinate, radiusMeters: largest, category: category)
            if let bigger = memoryCache.object(forKey: largestKey) {
                let filtered = bigger.pois.filter { poi in
                    Self.haversineMeters(
                        lat1: coordinate.latitude, lon1: coordinate.longitude,
                        lat2: poi.lat, lon2: poi.lon
                    ) <= Double(radiusMeters)
                }
                memoryCache.setObject(CachedPOIs(filtered), forKey: cacheKey)
                Self.logger.info("♻️ amap cache reuse r=\(radiusMeters, privacy: .public)m from r=\(largest, privacy: .public)m: \(filtered.count, privacy: .public)/\(bigger.pois.count, privacy: .public)")
                return filtered
            }
        }

        // In-flight dedup: a concurrent caller waiting on the same key reuses
        // the same Task instead of issuing a parallel HTTP request. Wrapping
        // the network/parse pipeline in a Task makes it observable to peers
        // BEFORE the first await suspends, eliminating the duplicate-burst
        // window that progressiveRadii fan-out + user re-taps could open.
        if let inflight = inFlight[cacheKey] {
            return try await inflight.value
        }

        let task = Task { [self, key, coordinate, radiusMeters, category, cacheKey, centerKey] in
            try await self.performFetch(
                key: key,
                coordinate: coordinate,
                radiusMeters: radiusMeters,
                category: category,
                cacheKey: cacheKey,
                centerKey: centerKey
            )
        }
        inFlight[cacheKey] = task
        defer { inFlight[cacheKey] = nil }
        return try await task.value
    }

    /// Issue the actual paginated /v5/place/around request — extracted so the
    /// in-flight dedup wrapper above can register the Task before any await
    /// suspension point. Side-effects: populates `memoryCache` and updates
    /// `largestFetchedRadius` for subsequent local-filter reuse.
    private func performFetch(
        key: String,
        coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        category: ExperienceCategory?,
        cacheKey: NSString,
        centerKey: NSString
    ) async throws -> [OverpassService.POI] {
        let gcj = CoordinateConverter.wgs84ToGcj02(coordinate)

        isFetching = true
        defer { isFetching = false }

        // Amap caps page_size at 25. Paginate up to maxResults (default 75).
        let pageSize = 25
        let maxPages = max(1, (maxResults + pageSize - 1) / pageSize)
        var allPois: [OverpassService.POI] = []
        var seenIds = Set<Int64>()

        for page in 1...maxPages {
            guard let url = Self.buildURL(
                key: key,
                gcjCenter: gcj,
                radiusMeters: radiusMeters,
                category: category,
                pageSize: pageSize,
                pageNum: page
            ) else {
                throw AmapError.requestFailed(status: -1)
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("SoloCompass-iOS/1.0", forHTTPHeaderField: "User-Agent")

            // Retry only on URLError (timeout / connection lost) — common on
            // mainland mobile networks. HTTP non-2xx and business errors
            // (status="0") are NOT retried: they indicate a permanent problem
            // (bad key, quota, signature) that another request won't fix.
            let (data, response) = try await Self.fetchWithRetry(request: request, session: session)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw AmapError.requestFailed(status: status)
            }

            let decoded = try JSONDecoder().decode(AroundResponse.self, from: data)
            guard decoded.status == "1" else {
                // Map well-known infocodes to actionable hints so the developer
                // sees "需要在控制台关数字签名" instead of just an opaque "10009".
                let hint = Self.infocodeHint(decoded.infocode)
                let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                Self.logger.error("⚠️ amap fail status=\(decoded.status, privacy: .public) infocode=\(decoded.infocode ?? "nil", privacy: .public) hint=\(hint, privacy: .public) info=\(decoded.info ?? "nil", privacy: .public) raw=\(String(raw.prefix(240)), privacy: .public)")
                break
            }

            for amap in (decoded.pois ?? []) {
                guard let poi = Self.poi(from: amap) else { continue }
                // Quality gate: drop utility/infrastructure junk (ATMs, parking,
                // offices, clinics…) and clearly bad venues before they ever
                // reach the merge — the whole point is 精品/旅游, not "whatever
                // is physically nearest".
                guard Self.isQualityPOI(
                    name: poi.name,
                    typecode: amap.typecode,
                    rating: amap.business?.rating
                ) else { continue }
                if seenIds.contains(poi.osmId) { continue }
                seenIds.insert(poi.osmId)
                allPois.append(poi)
                // Stash the raw amap signals (rating / hours / tel / addr)
                // in the TRANSIENT enrichment table — never persisted, only
                // consumed by AIService.synthesizeExperiences as prompt context.
                // Per ADR §3.2 these must not enter SwiftData; the consumer's
                // contract is "read once and discard" via consumeEnrichments.
                if amap.business?.rating != nil
                    || amap.business?.opentimeToday != nil
                    || (amap.tel?.isEmpty == false)
                    || (amap.address?.isEmpty == false) {
                    transientEnrichments[poi.osmId] = TransientAmapEnrichment(
                        rating: amap.business?.rating,
                        opentimeToday: amap.business?.opentimeToday,
                        phone: amap.tel,
                        address: amap.address
                    )
                }
            }
            let pagePoisCount = (decoded.pois ?? []).count

            // Stop if this page returned fewer than pageSize (no more data).
            // Note: counts raw decoded pois (before dedup) so a partial last
            // page still terminates correctly even if every POI was a dup.
            if pagePoisCount < pageSize { break }
            if allPois.count >= maxResults { break }
        }

        memoryCache.setObject(CachedPOIs(allPois), forKey: cacheKey)
        // Record the largest radius we've fetched for this (center, category)
        // so a subsequent smaller-radius call can filter locally (see fetchPOIs
        // entry: "Reuse a strictly larger same-(center, category) fetch...").
        let prevLargest = largestFetchedRadius[centerKey] ?? 0
        if radiusMeters > prevLargest {
            largestFetchedRadius[centerKey] = radiusMeters
        }
        return allPois
    }

    // MARK: - URL building

    static func buildURL(
        key: String,
        gcjCenter: CLLocationCoordinate2D,
        radiusMeters: Int,
        category: ExperienceCategory?,
        pageSize: Int,
        pageNum: Int = 1
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
            URLQueryItem(name: "page_num", value: String(pageNum)),
            // Sort by Amap's composite weight (popularity + quality) rather than
            // raw distance. Under `distance` the nearest ATM/parking-lot/office
            // beat the landmark two blocks away; `weight` lets Amap's own
            // quality ranking decide which POIs survive the page cap.
            URLQueryItem(name: "sortrule", value: "weight"),
            // Ask for the richer field set (business hours, rating, etc.) so
            // synthesis can cite real signals.
            URLQueryItem(name: "show_fields", value: "business,indoor")
        ]
        // A typed category maps to its own codes; a broad search (nil category,
        // or `.hidden` which intentionally maps to nil) is constrained to the
        // curated tourism whitelist instead of "everything nearby" — an untyped
        // /around query returns banks, offices, and parking lots, which is
        // exactly the garbage the explore pipeline used to synthesize.
        let types = category.flatMap(amapTypes(for:)) ?? broadTourismTypes
        items.append(URLQueryItem(name: "types", value: types))
        comps?.queryItems = items
        return comps?.url
    }

    /// Curated typecode whitelist for broad (untyped) searches. Tourism-first:
    /// sights (11), culture/museums (14), real dining (0501 中餐厅 / 0502 外国
    /// 餐厅 — deliberately excluding 0503 快餐厅), coffee/tea/dessert
    /// (0505/0506/0509), and entertainment venues (0803). Everything a solo
    /// traveler might actually walk to; nothing they wouldn't.
    static let broadTourismTypes = "110000|140000|050100|050200|050500|050600|050900|080300"

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

    // MARK: - Quality gate

    /// Amap top-level classes that are never travel-relevant, regardless of
    /// what the request asked for (a types-filtered query can still return
    /// mixed classes for multi-typecode venues). 01–04 汽车/摩托, 07 生活服务,
    /// 10 住宿, 12 商务住宅, 13 政府机构, 15 交通设施, 16 金融保险, 17 公司企业,
    /// 18 道路附属, 19 地名地址, 20 公共设施 — plus 0503 快餐厅 (chain fast food
    /// is not 精品 by definition).
    static let blockedTypePrefixes: [String] = [
        "01", "02", "03", "04", "07", "10", "12", "13",
        "15", "16", "17", "18", "19", "20", "0503"
    ]

    /// Name substrings that mark a POI as utility/infrastructure noise even
    /// when its typecode looks acceptable (Amap tagging in the wild is messy:
    /// bank branches under 05, property offices under 14…). Skipped for
    /// scenic-class POIs (11) so e.g. 银行博物馆 isn't false-positived away.
    static let junkNamePatterns: [String] = [
        "ATM", "自助银行", "停车场", "停车库", "公厕", "公共厕所", "洗手间",
        "加油站", "加气站", "充电站", "充电桩", "营业厅", "售楼", "物业",
        "快递", "驿站", "菜鸟", "彩票", "药店", "药房", "大药房", "银行",
        "信用社", "证券", "保险", "诊所", "医院", "门诊", "口腔", "体检",
        "理发", "美发", "洗车", "汽修", "4S店", "幼儿园", "小学", "中学",
        "培训", "驾校", "便利店", "超市", "有限公司", "事务所", "殡仪",
        "公墓", "墓园", "派出所", "警务", "税务局", "工商局", "居委会", "村委会"
    ]

    /// Minimum acceptable Amap rating when one is present. Unrated POIs pass
    /// (plenty of genuinely good places have no rating yet); a place that HAS
    /// been rated and sits below this is a confirmed dud.
    static let minAcceptableRating: Double = 3.0

    /// The 精品/旅游 gate applied to every fetched POI before caching/merging.
    /// Three checks, cheapest first: typecode blocklist → junk-name patterns
    /// (scenic class 11 exempt) → rated-and-bad floor.
    static func isQualityPOI(name: String, typecode: String?, rating: String?) -> Bool {
        if let code = typecode {
            for prefix in blockedTypePrefixes where code.hasPrefix(prefix) {
                return false
            }
        }
        let isScenic = typecode?.hasPrefix("11") == true
        if !isScenic {
            for pattern in junkNamePatterns where name.localizedCaseInsensitiveContains(pattern) {
                return false
            }
        }
        if let ratingStr = rating, let value = Double(ratingStr),
           value > 0, value < minAcceptableRating {
            return false
        }
        return true
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
    /// Rejects NaN / infinite / out-of-range values so a malformed response
    /// can't poison the in-memory cache or crash MapKit annotation rendering.
    static func parseLocation(_ s: String) -> CLLocationCoordinate2D? {
        let parts = s.split(separator: ",")
        guard parts.count == 2,
              let lon = Double(parts[0]),
              let lat = Double(parts[1]),
              lon.isFinite, lat.isFinite,
              abs(lat) <= 90, abs(lon) <= 180,
              !(lat == 0 && lon == 0) // null-island sentinel
        else { return nil }
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

    /// Radius-agnostic key, used to look up the largest-radius cached result
    /// for the same (center, category) — the basis for `progressiveRadii`
    /// local filtering reuse.
    private static func centerCacheKey(
        coordinate: CLLocationCoordinate2D,
        category: ExperienceCategory?
    ) -> NSString {
        let lat = (coordinate.latitude * 10_000).rounded() / 10_000
        let lon = (coordinate.longitude * 10_000).rounded() / 10_000
        let cat = category?.rawValue ?? "all"
        return "\(lat),\(lon)_\(cat)" as NSString
    }

    /// Haversine great-circle distance in meters between two WGS84 points.
    /// Used to filter a cached larger-radius result into a smaller-radius
    /// subset locally instead of re-querying amap.
    static func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6_371_000.0
        let φ1 = lat1 * .pi / 180
        let φ2 = lat2 * .pi / 180
        let Δφ = (lat2 - lat1) * .pi / 180
        let Δλ = (lon2 - lon1) * .pi / 180
        let a = sin(Δφ / 2) * sin(Δφ / 2) +
                cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    // MARK: - Retry

    /// Retry transient URLErrors with exponential backoff. 3 total attempts
    /// (initial + 2 retries), 1s/2s. Business errors (HTTP non-2xx, Amap
    /// status="0") are intentionally NOT retried — they indicate a config
    /// issue (bad key, quota exhausted, signature) that won't fix itself.
    static func fetchWithRetry(request: URLRequest, session: URLSession, attempts: Int = 3) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 1...attempts {
            do {
                return try await session.data(for: request)
            } catch let urlError as URLError {
                lastError = urlError
                let transient: Set<URLError.Code> = [
                    .timedOut, .networkConnectionLost, .notConnectedToInternet,
                    .dnsLookupFailed, .cannotConnectToHost, .cannotFindHost
                ]
                guard transient.contains(urlError.code), attempt < attempts else { throw urlError }
                let delayNs = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                logger.warning("⚠️ amap network retry \(attempt, privacy: .public)/\(attempts - 1, privacy: .public) after \(urlError.code.rawValue, privacy: .public)")
                try? await Task.sleep(nanoseconds: delayNs)
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    // MARK: - Infocode mapping

    /// Map Amap infocode to an actionable English hint. Covers the codes that
    /// surface most often in the wild; anything else is reported as "unknown".
    /// Reference: https://lbs.amap.com/api/webservice/guide/tools/info
    static func infocodeHint(_ code: String?) -> String {
        guard let code else { return "unknown (no infocode)" }
        switch code {
        case "10000": return "OK"
        case "10001": return "INVALID_KEY — key 错误或被吊销，检查 .env AMAP_API_KEY"
        case "10003": return "DAILY_QUERY_OVER_LIMIT — 当日配额耗尽"
        case "10004": return "ACCESS_TOO_FREQUENT — 单位时间访问次数超限"
        case "10005": return "INVALID_USER_IP — 调用方 IP 异常"
        case "10008": return "INVALID_USER_DOMAIN — bundle id 与控制台不匹配"
        case "10009": return "INVALID_USER_GROUP_COUNT — 通常为数字签名校验失败，控制台关闭'数字签名校验'或补 sig 参数"
        case "10012": return "INSUFFICIENT_PRIVILEGES — 服务未开通，控制台启用 'Web 服务 API → 搜索 POI 2.0'"
        case "10014": return "USER_DAILY_QUERY_OVER_LIMIT — 个人每日配额耗尽"
        case "10019": return "USER_KEY_RECYCLED — key 已回收"
        case "10044": return "USER_DAY_QUERY_OVER_LIMIT — 当日额度达上限"
        case "10045": return "USER_ACCESS_TOO_FREQUENT — 服务 QPS 超限"
        case "20000": return "INVALID_PARAMS — 请求参数非法 (检查 location/radius/types)"
        case "20001": return "MISSING_REQUIRED_PARAMS — 必填参数缺失"
        case "20003": return "UNKNOWN_ERROR — 高德服务端未知错误，可重试"
        default: return "unmapped infocode=\(code)"
        }
    }

    // MARK: - Decodable shapes (Amap /v5/place/around)

    struct AroundResponse: Decodable {
        let status: String
        let info: String?
        let infocode: String?
        let pois: [AmapPOI]?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Amap historically returns status/infocode as string ("1"/"10000"),
            // but defensive decode accepts int too — typeMismatch would otherwise
            // null the whole response and the EnrichmentAgent silently falls back
            // to Overpass with no diagnostic.
            status = try Self.decodeFlexibleString(c, key: .status) ?? ""
            infocode = try Self.decodeFlexibleString(c, key: .infocode)
            info = try c.decodeIfPresent(String.self, forKey: .info)
            pois = try c.decodeIfPresent([AmapPOI].self, forKey: .pois)
        }

        private enum CodingKeys: String, CodingKey {
            case status, info, infocode, pois
        }

        private static func decodeFlexibleString(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> String? {
            if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s }
            if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return String(i) }
            return nil
        }
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

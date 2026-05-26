import Foundation
import CoreLocation
import Observation

/// Secondary POI data source used as a fallback when Overpass returns a thin
/// result set (e.g., cities with sparse OSM coverage). Mirrors the public
/// surface of `OverpassService.fetchPOIs(near:radiusMeters:category:)` so the
/// `MapViewModel.exploreNearby` pipeline can merge results from both sources
/// using the same downstream code path (AI synthesis, dedupe, append).
///
/// Returns `OverpassService.POI` instances so callers don't need a separate
/// adapter step. Foursquare's `fsq_id` is hashed into a stable `Int64` and
/// shifted into a high-bit range to avoid collisions with real OSM ids.
///
/// Uses the v3 Places API (`/places/search`). Auth via `Authorization` header
/// (the API key resolved from `Secrets.resolvedFoursquareKey`).
///
/// US-013: hard daily cap is not enforced here; `UserPreferences.foursquareCallsToday`
/// is incremented by the caller for visibility only.
@MainActor
@Observable
public final class FoursquareService {
    public enum FoursquareError: Error, LocalizedError {
        case invalidURL
        case missingAPIKey
        case requestFailed(status: Int)
        case decodingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidURL:
                return NSLocalizedString("foursquare.error.url", comment: "Invalid Foursquare URL")
            case .missingAPIKey:
                return NSLocalizedString("foursquare.error.missingKey", comment: "Foursquare API key missing")
            case .requestFailed(let status):
                return String(format: NSLocalizedString("foursquare.error.request", comment: "Foursquare request failed status %d"), status)
            case .decodingFailed(let msg):
                return msg
            }
        }
    }

    public private(set) var isFetching: Bool = false

    private let session: URLSession
    private let endpoint = URL(string: "https://api.foursquare.com/v3/places/search")
    private let maxResults: Int
    private let apiKeyProvider: @Sendable () -> String

    public init(
        session: URLSession = .shared,
        maxResults: Int = 30,
        apiKeyProvider: (@Sendable () -> String)? = nil
    ) {
        self.session = session
        self.maxResults = maxResults
        // Default to Secrets.resolvedFoursquareKey when no provider is
        // injected. Wrapped in a closure here (instead of a default arg
        // value) because `Secrets` is internal and can't be referenced
        // from a public init's default argument.
        self.apiKeyProvider = apiKeyProvider ?? { Secrets.resolvedFoursquareKey }
    }

    // MARK: - Public

    /// Fetch up to `maxResults` POIs within `radiusMeters` of the coordinate.
    /// Returns `OverpassService.POI` so results can be merged directly with
    /// Overpass output. Throws `.missingAPIKey` when no key is configured —
    /// callers should gate on `Secrets.resolvedFoursquareKey.isEmpty` first.
    public func fetchPOIs(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Int = 3000,
        category: ExperienceCategory? = nil
    ) async throws -> [OverpassService.POI] {
        let key = apiKeyProvider()
        guard !key.isEmpty else { throw FoursquareError.missingAPIKey }
        guard let endpoint else { throw FoursquareError.invalidURL }

        isFetching = true
        defer { isFetching = false }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "radius", value: String(radiusMeters)),
            URLQueryItem(name: "limit", value: String(maxResults)),
            URLQueryItem(name: "sort", value: "DISTANCE"),
            // Request the enrichment fields the deep-dive pipeline cares about.
            // Foursquare returns whatever the key's tier permits; missing fields
            // simply decode as nil and the POI keeps its OSM-only signal set.
            URLQueryItem(name: "fields", value: Self.requestedFields)
        ]
        if let category, let fsqCategories = Self.categoryToFoursquareIds[category] {
            items.append(URLQueryItem(name: "categories", value: fsqCategories))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw FoursquareError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SoloCompass-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FoursquareError.requestFailed(status: 0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FoursquareError.requestFailed(status: http.statusCode)
        }
        return try Self.decodePOIs(from: data)
    }

    /// Comma-separated `fields` requested from `/places/search`. `fsq_id`,
    /// `name`, `geocodes`, `categories` are the baseline; the rest are the
    /// "hard signals" the deep-dive enrichment pipeline surfaces to the AI.
    /// A free-tier key may silently omit `rating`/`hours`/`price` — those just
    /// decode as nil, so requesting them is always safe.
    static let requestedFields = "fsq_id,name,geocodes,categories,rating,hours,price,website,tel,popularity"

    // MARK: - Category mapping

    /// Maps a Solo Compass category to a comma-separated list of Foursquare v3
    /// category ids. Kept deliberately small — Foursquare's taxonomy is huge,
    /// but we only need parity with the Overpass filter buckets used elsewhere.
    static let categoryToFoursquareIds: [ExperienceCategory: String] = [
        .coffee: "13032,13035",                          // Cafe, Coffee Shop
        .food: "13065",                                  // Restaurant
        .nightlife: "13003,13029",                       // Bar, Pub
        .work: "12013,12080",                            // Library, Coworking Space
        .culture: "10027,10031,10004",                   // Museum, Art Gallery, Historic Site
        .nature: "16032,16036,16003",                    // Park, Garden, Beach
        .wellness: "18021,11147",                        // Spa, Wellness
        .hidden: "16000"                                  // Outdoors / scenic catch-all
    ]

    // MARK: - Decode

    /// Decode Foursquare `/places/search` JSON into POI rows. Skips entries
    /// missing a name or coordinate. Maps `fsq_id` (string) onto a stable
    /// `Int64` in the high-bit range so it never collides with real OSM ids.
    static func decodePOIs(from data: Data) throws -> [OverpassService.POI] {
        struct Wrapper: Decodable {
            let results: [Row]
        }
        struct Row: Decodable {
            let fsq_id: String
            let name: String?
            let geocodes: Geocodes?
            let categories: [Category]?
            // Enrichment fields — all optional; a free-tier key omits them.
            let rating: Double?       // 0–10
            let hours: Hours?
            let price: Int?           // 1–4
            let website: String?
            let tel: String?
            let popularity: Double?   // 0–1
        }
        struct Geocodes: Decodable {
            let main: LatLon?
        }
        struct LatLon: Decodable {
            let latitude: Double
            let longitude: Double
        }
        struct Category: Decodable {
            let id: Int?
            let name: String?
        }
        struct Hours: Decodable {
            let display: String?      // human-readable, e.g. "Mon-Fri 8:00 AM-6:00 PM"
            let open_now: Bool?
        }

        do {
            let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
            return wrapper.results.compactMap { row -> OverpassService.POI? in
                guard
                    let name = row.name, !name.isEmpty,
                    let coord = row.geocodes?.main
                else { return nil }
                var tags: [String: String] = ["name": name, "source": "foursquare", "fsq_id": row.fsq_id]
                if let firstCat = row.categories?.first?.name {
                    tags["amenity"] = mapFoursquareCategoryToAmenity(firstCat)
                }
                // Hard signals — namespaced under fsq_ so downstream code (the
                // enrichment merge + AI prompt builder) can distinguish them
                // from raw OSM tags and cite them as real provider data.
                if let rating = row.rating { tags["fsq_rating"] = String(rating) }
                if let hours = row.hours?.display, !hours.isEmpty { tags["opening_hours"] = hours }
                if let price = row.price { tags["fsq_price"] = String(price) }
                if let website = row.website, !website.isEmpty { tags["website"] = website }
                if let tel = row.tel, !tel.isEmpty { tags["phone"] = tel }
                if let popularity = row.popularity { tags["fsq_popularity"] = String(popularity) }
                let stableId = stableInt64Id(forFsqId: row.fsq_id)
                return OverpassService.POI(
                    osmId: stableId,
                    name: name,
                    nameEn: nil,
                    lat: coord.latitude,
                    lon: coord.longitude,
                    tags: tags
                )
            }
        } catch {
            throw FoursquareError.decodingFailed(String(describing: error))
        }
    }

    /// Best-effort coarse bucket: produce a value compatible with
    /// `OverpassService.category(for:)` from a Foursquare category name.
    private static func mapFoursquareCategoryToAmenity(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("coffee") || lower.contains("cafe") { return "cafe" }
        if lower.contains("restaurant") { return "restaurant" }
        if lower.contains("bar") { return "bar" }
        if lower.contains("pub") { return "pub" }
        if lower.contains("library") { return "library" }
        if lower.contains("coworking") { return "coworking_space" }
        if lower.contains("spa") { return "spa" }
        return lower
    }

    /// Hash a Foursquare `fsq_id` string into a stable `Int64`. Sets a high
    /// marker bit so the result never collides with real OSM ids (which are
    /// positive and well below 2^62). Same string → same id across runs.
    static func stableInt64Id(forFsqId fsqId: String) -> Int64 {
        var hash: UInt64 = 1469598103934665603 // FNV offset basis
        for byte in fsqId.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211 // FNV prime
        }
        let positive = hash & 0x7FFF_FFFF_FFFF_FFFF
        return Int64(bitPattern: positive | 0x4000_0000_0000_0000)
    }

    // MARK: - Merge

    /// Merge Overpass + Foursquare POIs, dedup'd by 4-decimal coordinate cell
    /// (~11 m). When both sources contain a POI in the same cell, the
    /// Overpass record is kept (OSM data is generally richer for our use).
    /// Preserves input order of `overpass` first, then appends any non-dupe
    /// Foursquare entries in their original order.
    public static func merge(
        overpass: [OverpassService.POI],
        foursquare: [OverpassService.POI]
    ) -> [OverpassService.POI] {
        var seen = Set<String>()
        var result: [OverpassService.POI] = []
        for poi in overpass {
            let key = cellKey(lat: poi.lat, lon: poi.lon)
            if seen.insert(key).inserted {
                result.append(poi)
            }
        }
        for poi in foursquare {
            let key = cellKey(lat: poi.lat, lon: poi.lon)
            if seen.insert(key).inserted {
                result.append(poi)
            }
        }
        return result
    }

    /// 4-decimal lat/lon bucket key used by `merge`. Two POIs whose
    /// coordinates round to the same cell (~11 m) are considered duplicates.
    static func cellKey(lat: Double, lon: Double) -> String {
        let rLat = (lat * 10_000).rounded() / 10_000
        let rLon = (lon * 10_000).rounded() / 10_000
        return String(format: "%.4f_%.4f", rLat, rLon)
    }

    /// Enrichment merge used by the deep-dive pipeline. Unlike `merge` — which
    /// keeps one POI per cell and discards the other — this folds the *signal*
    /// tags from `enrichment` POIs INTO the matching `base` POI in the same
    /// cell, so an OSM/MapKit place gains Foursquare's rating/hours/price
    /// without losing its identity. Enrichment-only cells (no base match) are
    /// appended as standalone POIs.
    ///
    /// Only the hard-signal keys are folded; `base`'s own tags win on any
    /// key collision so we never overwrite a more authoritative source name.
    static func enrichMerge(
        base: [OverpassService.POI],
        enrichment: [OverpassService.POI]
    ) -> [OverpassService.POI] {
        let signalKeys = ["fsq_rating", "opening_hours", "fsq_price", "website", "phone", "fsq_popularity", "addr"]
        // Index enrichment POIs by cell for O(1) lookup.
        var enrichmentByCell: [String: OverpassService.POI] = [:]
        for poi in enrichment {
            enrichmentByCell[cellKey(lat: poi.lat, lon: poi.lon), default: poi] = poi
        }

        var usedCells = Set<String>()
        var result: [OverpassService.POI] = []
        for poi in base {
            let key = cellKey(lat: poi.lat, lon: poi.lon)
            usedCells.insert(key)
            guard let match = enrichmentByCell[key] else {
                result.append(poi)
                continue
            }
            var tags = poi.tags
            for sk in signalKeys where tags[sk] == nil {
                if let value = match.tags[sk] { tags[sk] = value }
            }
            result.append(OverpassService.POI(
                osmId: poi.osmId,
                name: poi.name,
                nameEn: poi.nameEn,
                lat: poi.lat,
                lon: poi.lon,
                tags: tags
            ))
        }
        // Enrichment-only cells become standalone POIs.
        for poi in enrichment {
            let key = cellKey(lat: poi.lat, lon: poi.lon)
            if usedCells.insert(key).inserted {
                result.append(poi)
            }
        }
        return result
    }
}

import Foundation
import CoreLocation
import Observation

/// Talks to the public Overpass API (OpenStreetMap) to fetch real-world POIs
/// near a coordinate. Used by the "Explore here" feature so users in cities
/// outside our seed data still get something on the map.
///
/// Overpass is free, key-less, and globally covered, but rate-limited
/// (~10k queries/day per IP on the public instance). We cap query size and
/// give the caller a single retry on transient failures.
///
/// Data attribution: © OpenStreetMap contributors (ODbL). Surfaces must show this.
@Observable
public final class OverpassService {
    /// A single OSM POI we care about — name + coordinate + raw tags.
    public struct POI: Codable, Hashable, Identifiable {
        public let osmId: Int64
        public let name: String
        public let nameEn: String?
        public let lat: Double
        public let lon: Double
        public let tags: [String: String]

        public var id: Int64 { osmId }

        public var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        public init(osmId: Int64, name: String, nameEn: String?, lat: Double, lon: Double, tags: [String: String]) {
            self.osmId = osmId
            self.name = name
            self.nameEn = nameEn
            self.lat = lat
            self.lon = lon
            self.tags = tags
        }
    }

    public enum OverpassError: Error, LocalizedError {
        case invalidURL
        case requestFailed(status: Int)
        case decodingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidURL:
                return NSLocalizedString("overpass.error.url", comment: "Invalid Overpass URL")
            case .requestFailed(let status):
                return String(format: NSLocalizedString("overpass.error.request", comment: "Overpass request failed status %d"), status)
            case .decodingFailed(let msg):
                return msg
            }
        }
    }

    public private(set) var isFetching: Bool = false

    private let session: URLSession
    private let endpoint = URL(string: "https://overpass-api.de/api/interpreter")
    private let maxResults: Int
    private let repository: ExperienceRepository?

    /// Cache TTL — 14 days. Outside this window we re-fetch from
    /// Overpass. (See PRD US-B1.)
    public static let cacheTTLSeconds: TimeInterval = 14 * 86_400

    public init(
        session: URLSession = .shared,
        maxResults: Int = 30,
        repository: ExperienceRepository? = nil
    ) {
        self.session = session
        self.maxResults = maxResults
        self.repository = repository
    }

    /// Convenience init that uses the shared SwiftData container's main
    /// context for caching. Pass `nil` (default of designated init) in
    /// tests if you want cache disabled.
    /// `@MainActor` required because `ExperienceRepository` is `@MainActor`-isolated
    /// (it owns a SwiftData `ModelContext` which is bound to the main actor).
    @MainActor
    public convenience init(session: URLSession = .shared, maxResults: Int = 30, useSharedCache: Bool) {
        let repo: ExperienceRepository? = useSharedCache
            ? ExperienceRepository()
            : nil
        self.init(session: session, maxResults: maxResults, repository: repo)
    }

    // MARK: - Public

    /// Fetch up to `maxResults` POIs within `radiusMeters` of the coordinate.
    /// Cache hit: returns persisted POIs without HTTP. Cache miss:
    /// performs a real fetch with 1 retry, writes through to cache.
    ///
    /// When `category` is non-nil, the Overpass query is narrowed to
    /// tag filters from `categoryToOverpassFilter` — so tapping the
    /// Coffee pill returns coffee shops, not a generic mix.
    public func fetchPOIs(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Int = 3000,
        category: ExperienceCategory? = nil
    ) async throws -> [POI] {
        let regionKey = Self.regionKey(
            lat: coordinate.latitude,
            lon: coordinate.longitude,
            radiusMeters: radiusMeters,
            category: category
        )

        if let cached = await loadCached(regionKey: regionKey) {
            return cached
        }

        guard let endpoint else { throw OverpassError.invalidURL }
        await MainActor.run { self.isFetching = true }
        defer { Task { @MainActor [weak self] in self?.isFetching = false } }

        let query = Self.buildQuery(
            lat: coordinate.latitude,
            lon: coordinate.longitude,
            radiusMeters: radiusMeters,
            limit: maxResults,
            category: category
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("SoloCompass-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        request.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")".data(using: .utf8)

        let (raw, pois) = try await fetchAndDecode(request)
        await writeCache(regionKey: regionKey, raw: raw, poiCount: pois.count)
        return pois
    }

    /// Public cache-clear; used by Settings → Storage.
    @MainActor
    public func clearExploreCache() {
        repository?.clearExploreCache()
    }

    /// Deterministic key for a (lat, lon, radius) cell. Rounding to
    /// 0.01° (~1.1 km) means small map pans still hit the same cache
    /// row.
    /// Flatten a list of per-ring POI batches into a single deduplicated
    /// list, keyed by `osmId`. Earlier batches (inner rings) win — when a
    /// POI appears in both R1 and R2 we keep the R1 copy. Preserves input
    /// order within each batch.
    ///
    /// Used by the Pro multi-ring Explore (US-MR-02) to merge the outputs
    /// of 4 concurrent Overpass calls before handing the result to a
    /// single AI synthesis. See docs/PRD/pro-radial-explore.md.
    public static func dedupe(across batches: [[POI]]) -> [POI] {
        var seen = Set<Int64>()
        var result: [POI] = []
        for batch in batches {
            for poi in batch where seen.insert(poi.osmId).inserted {
                result.append(poi)
            }
        }
        return result
    }

    public static func regionKey(
        lat: Double,
        lon: Double,
        radiusMeters: Int,
        category: ExperienceCategory? = nil
    ) -> String {
        let roundedLat = (lat * 100).rounded() / 100
        let roundedLon = (lon * 100).rounded() / 100
        let base = String(format: "%.2f_%.2f_%d", roundedLat, roundedLon, radiusMeters)
        if let category {
            return "\(base)_\(category.rawValue)"
        }
        return base
    }

    // MARK: - HTTP

    /// One-attempt-with-retry fetch that returns the raw JSON and the
    /// decoded POIs together — we want both: POIs for the caller, raw
    /// JSON for cache write-through.
    private func fetchAndDecode(_ request: URLRequest) async throws -> (Data, [POI]) {
        do {
            return try await performAndDecode(request)
        } catch {
            try? await Task.sleep(nanoseconds: 800_000_000)
            return try await performAndDecode(request)
        }
    }

    private func performAndDecode(_ request: URLRequest) async throws -> (Data, [POI]) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OverpassError.requestFailed(status: 0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OverpassError.requestFailed(status: http.statusCode)
        }
        return (data, try Self.decodePOIs(from: data))
    }

    // MARK: - Cache

    /// async-bridge: fetchPOIs is nonisolated, ExperienceRepository is MainActor.
    private func loadCached(regionKey key: String) async -> [POI]? {
        await MainActor.run { [weak self] in
            guard let self, let repo = self.repository else { return nil }
            guard let raw = repo.loadExploreCache(regionKey: key) else { return nil }
            return try? Self.decodePOIs(from: raw)
        }
    }

    private func writeCache(regionKey key: String, raw: Data, poiCount: Int) async {
        await MainActor.run { [weak self] in
            guard let self, let repo = self.repository else { return }
            repo.writeExploreCache(regionKey: key, raw: raw, poiCount: poiCount)
        }
    }

    // MARK: - Query

    /// Single source of truth for narrowing an Explore-here query to a
    /// specific Solo Compass category. Each value is one or more
    /// Overpass QL `node[...](around)` clauses (newline-joined) that
    /// will be substituted into the union body of `buildQuery` when a
    /// caller passes `category:` to `fetchPOIs`.
    ///
    /// The filters are deliberately a subset of the broader tag set
    /// used by the generic (category == nil) query, so any POI returned
    /// here will round-trip back to the same `ExperienceCategory` via
    /// `category(for:)`.
    public static let categoryToOverpassFilter: [ExperienceCategory: String] = [
        .coffee: ##"""
        node["amenity"="cafe"](AROUND);
        node["shop"~"^(coffee|tea)$"](AROUND);
        """##,
        .work: ##"""
        node["amenity"="coworking_space"](AROUND);
        node["amenity"="library"](AROUND);
        """##,
        .nature: ##"""
        node["leisure"~"^(park|garden|nature_reserve)$"](AROUND);
        node["natural"~"^(beach|peak|hot_spring|wood|water)$"](AROUND);
        """##,
        .culture: ##"""
        node["tourism"~"^(attraction|gallery|museum|artwork)$"](AROUND);
        node["historic"](AROUND);
        """##,
        .food: ##"""
        node["amenity"~"^(restaurant|fast_food|food_court)$"](AROUND);
        """##,
        .wellness: ##"""
        node["leisure"="spa"](AROUND);
        node["amenity"="spa"](AROUND);
        node["healthcare"](AROUND);
        """##,
        .nightlife: ##"""
        node["amenity"~"^(bar|pub|nightclub)$"](AROUND);
        """##,
        .hidden: ##"""
        node["tourism"="viewpoint"](AROUND);
        """##
    ]

    static func buildQuery(
        lat: Double,
        lon: Double,
        radiusMeters: Int,
        limit: Int,
        category: ExperienceCategory? = nil
    ) -> String {
        let around = "around:\(radiusMeters),\(lat),\(lon)"
        let body: String
        if let category, let filter = categoryToOverpassFilter[category] {
            body = filter.replacingOccurrences(of: "AROUND", with: around)
        } else {
            body = """
            node["amenity"~"^(restaurant|cafe|bar|pub|fast_food|ice_cream|food_court|library|coworking_space|spa)$"](\(around));
            node["tourism"~"^(attraction|viewpoint|gallery|museum|artwork|zoo|aquarium)$"](\(around));
            node["leisure"~"^(park|garden|nature_reserve|fitness_centre)$"](\(around));
            node["natural"~"^(beach|peak|hot_spring)$"](\(around));
            node["shop"~"^(books|coffee|tea)$"](\(around));
            """
        }
        return """
        [out:json][timeout:15];
        (
        \(body)
        );
        out body \(limit);
        """
    }

    // MARK: - Decode

    static func decodePOIs(from data: Data) throws -> [POI] {
        struct Wrapper: Decodable {
            let elements: [Element]
        }
        struct Element: Decodable {
            let id: Int64
            let lat: Double?
            let lon: Double?
            let tags: [String: String]?
        }
        do {
            let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
            return wrapper.elements.compactMap { el -> POI? in
                guard let lat = el.lat, let lon = el.lon, let tags = el.tags else { return nil }
                let nameEn = tags["name:en"]
                let name = tags["name"] ?? nameEn ?? ""
                guard !name.isEmpty else { return nil }
                return POI(osmId: el.id, name: name, nameEn: nameEn, lat: lat, lon: lon, tags: tags)
            }
        } catch {
            throw OverpassError.decodingFailed(String(describing: error))
        }
    }

    // MARK: - Tag → category

    /// Map raw OSM tags to a Solo Compass `ExperienceCategory`. Ordering matters:
    /// more specific tags (e.g. coworking_space) win over generic ones.
    public static func category(for tags: [String: String]) -> ExperienceCategory {
        if let amenity = tags["amenity"] {
            switch amenity {
            case "cafe", "ice_cream":
                return .coffee
            case "restaurant", "fast_food", "food_court":
                return .food
            case "bar", "pub":
                return .nightlife
            case "library", "coworking_space":
                return .work
            case "spa":
                return .wellness
            default:
                break
            }
        }
        if let shop = tags["shop"] {
            switch shop {
            case "coffee", "tea":
                return .coffee
            case "books":
                return .work
            default:
                break
            }
        }
        if let tourism = tags["tourism"] {
            switch tourism {
            case "viewpoint":
                return .hidden
            case "attraction", "artwork", "gallery", "museum":
                return .culture
            case "zoo", "aquarium":
                return .nature
            default:
                break
            }
        }
        if let leisure = tags["leisure"] {
            switch leisure {
            case "park", "garden", "nature_reserve":
                return .nature
            case "fitness_centre":
                return .wellness
            default:
                break
            }
        }
        if tags["natural"] != nil {
            return .nature
        }
        return .hidden
    }
}

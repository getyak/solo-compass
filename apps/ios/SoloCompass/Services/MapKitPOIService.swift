import Foundation
import CoreLocation
import MapKit
import Observation

/// Tertiary POI data source backed by Apple's `MKLocalSearch`. Free, native,
/// key-less — used by the deep-dive enrichment pipeline to thicken the signal
/// set for each place beyond what OSM/Overpass exposes.
///
/// Returns `OverpassService.POI` instances (the canonical POI shape across the
/// app) so results merge through the same dedupe path as Overpass + Foursquare.
/// Apple's `MKMapItem` exposes `pointOfInterestCategory`, `phoneNumber`, and
/// `url`; we map the category to an OSM-style `amenity`/`tourism`/`leisure`
/// tag so `OverpassService.category(for:)` keeps working unchanged. Hours and
/// rating are not part of the public MapItem surface, so those stay nil here
/// (Foursquare is the rating/hours source).
///
/// `@MainActor` because `MKLocalSearch` completion is dispatched on the main
/// queue and the rest of the explore pipeline is main-actor-bound.
@MainActor
@Observable
public final class MapKitPOIService {
    /// Failures that can occur while searching nearby places via MapKit.
    public enum MapKitPOIError: Error, LocalizedError {
        case searchFailed(String)

        public var errorDescription: String? {
            switch self {
            case .searchFailed(let msg):
                return msg
            }
        }
    }

    public private(set) var isFetching: Bool = false

    public init() {}

    /// Search Apple Maps POIs within `radiusMeters` of `coordinate`. `category`
    /// narrows the `MKPointOfInterestCategory` filter when provided; otherwise
    /// the search returns the full POI set in the region. Best-effort — returns
    /// an empty array rather than throwing on an empty result so callers can
    /// treat it as a soft enrichment source.
    public func fetchPOIs(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Int = 1000,
        category: ExperienceCategory? = nil
    ) async throws -> [OverpassService.POI] {
        isFetching = true
        defer { isFetching = false }

        let request = MKLocalPointsOfInterestRequest(
            center: coordinate,
            radius: CLLocationDistance(radiusMeters)
        )
        if let category, let filter = Self.poiFilter(for: category) {
            request.pointOfInterestFilter = filter
        }

        let search = MKLocalSearch(request: request)
        let response: MKLocalSearch.Response
        do {
            response = try await search.start()
        } catch {
            // An empty-result search surfaces as an error on some OS versions;
            // treat that as "no POIs" rather than a hard failure.
            let ns = error as NSError
            if ns.domain == MKError.errorDomain {
                return []
            }
            throw MapKitPOIError.searchFailed(String(describing: error))
        }

        return response.mapItems.compactMap { Self.poi(from: $0) }
    }

    /// Free-text POI search — the missing piece the local card filter can't do.
    ///
    /// `MKLocalPointsOfInterestRequest` (used by `fetchPOIs`) can only return
    /// "everything of category X near a point"; it takes no query string. To
    /// answer "find me izakayas" the user must be able to *type* — that's what
    /// `MKLocalSearch.Request.naturalLanguageQuery` is for. We bias the results
    /// toward the user's current map region so "coffee" surfaces nearby cafes
    /// rather than a city across the country.
    ///
    /// Best-effort: an empty MapKit result (which surfaces as an `MKError` on
    /// some OS versions) degrades to `[]` rather than throwing, so the caller
    /// can render an honest "no results" state instead of an error banner.
    ///
    /// - Parameters:
    ///   - query: The raw, user-typed search string. Whitespace-trimmed here;
    ///     an empty query short-circuits to `[]` (no wasted network call).
    ///   - coordinate: Center of the region to bias results toward.
    ///   - radiusMeters: Half-span of the search region (default 20 km — wide
    ///     enough to cover a city, tight enough to stay locally relevant).
    public func search(
        query: String,
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Int = 20_000
    ) async throws -> [OverpassService.POI] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        isFetching = true
        defer { isFetching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: CLLocationDistance(radiusMeters * 2),
            longitudinalMeters: CLLocationDistance(radiusMeters * 2)
        )

        let search = MKLocalSearch(request: request)
        let response: MKLocalSearch.Response
        do {
            response = try await search.start()
        } catch {
            let ns = error as NSError
            if ns.domain == MKError.errorDomain {
                return []
            }
            throw MapKitPOIError.searchFailed(String(describing: error))
        }

        return response.mapItems.compactMap { Self.poi(from: $0) }
    }

    // MARK: - Mapping

    /// Convert an `MKMapItem` into an `OverpassService.POI`. Returns nil when
    /// the item has no name or usable coordinate.
    static func poi(from item: MKMapItem) -> OverpassService.POI? {
        let placemark = item.placemark
        let name = item.name ?? placemark.name
        guard let name, !name.isEmpty else { return nil }
        let coord = placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coord) else { return nil }

        var tags: [String: String] = ["name": name, "source": "mapkit"]
        if let osmTag = item.pointOfInterestCategory.flatMap(osmTag(for:)) {
            tags[osmTag.key] = osmTag.value
        }
        if let phone = item.phoneNumber, !phone.isEmpty {
            tags["phone"] = phone
        }
        if let url = item.url?.absoluteString, !url.isEmpty {
            tags["website"] = url
        }
        // A street-level address hint when the placemark carries one — helps
        // the AI write accurate howTo orientation steps.
        if let thoroughfare = placemark.thoroughfare {
            let withNumber = [placemark.subThoroughfare, thoroughfare]
                .compactMap { $0 }
                .joined(separator: " ")
            tags["addr"] = withNumber.isEmpty ? thoroughfare : withNumber
        }

        let stableId = stableInt64Id(forMapItem: item, name: name, coordinate: coord)
        return OverpassService.POI(
            osmId: stableId,
            name: name,
            nameEn: nil,
            lat: coord.latitude,
            lon: coord.longitude,
            tags: tags
        )
    }

    /// Map an `MKPointOfInterestCategory` to an OSM-style tag (key, value) so
    /// `OverpassService.category(for:)` resolves it to the right bucket.
    static func osmTag(for category: MKPointOfInterestCategory) -> (key: String, value: String)? {
        switch category {
        case .cafe, .bakery:
            return ("amenity", "cafe")
        case .restaurant, .foodMarket:
            return ("amenity", "restaurant")
        case .nightlife, .brewery, .winery:
            return ("amenity", "bar")
        case .library:
            return ("amenity", "library")
        case .museum:
            return ("tourism", "museum")
        case .nationalPark, .park:
            return ("leisure", "park")
        case .beach:
            return ("natural", "beach")
        case .fitnessCenter:
            return ("leisure", "fitness_centre")
        case .aquarium, .zoo:
            return ("tourism", "zoo")
        default:
            return nil
        }
    }

    /// Build an `MKPointOfInterestFilter` that narrows the search to the
    /// categories matching one of our `ExperienceCategory` buckets. Returns nil
    /// for buckets with no clean MapKit equivalent (caller then searches all).
    static func poiFilter(for category: ExperienceCategory) -> MKPointOfInterestFilter? {
        let categories: [MKPointOfInterestCategory]
        switch category {
        case .coffee:    categories = [.cafe, .bakery]
        case .food:      categories = [.restaurant, .foodMarket]
        case .nightlife: categories = [.nightlife, .brewery, .winery]
        case .work:      categories = [.library]
        case .culture:   categories = [.museum]
        case .nature:    categories = [.nationalPark, .park, .beach, .aquarium, .zoo]
        case .wellness:  categories = [.fitnessCenter]
        case .hidden:    return nil
        }
        return MKPointOfInterestFilter(including: categories)
    }

    /// Hash an Apple Maps item into a stable `Int64`. Apple has no public stable
    /// identifier, so we hash name + rounded coordinate. The high marker bit
    /// (0x2000…) is distinct from the OSM range and Foursquare's 0x4000… bit,
    /// so MapKit ids never collide with the other two sources.
    static func stableInt64Id(
        forMapItem item: MKMapItem,
        name: String,
        coordinate: CLLocationCoordinate2D
    ) -> Int64 {
        // 4-decimal coordinate (~11 m) keeps the id stable across runs even if
        // Apple jitters the coordinate slightly.
        let rLat = (coordinate.latitude * 10_000).rounded() / 10_000
        let rLon = (coordinate.longitude * 10_000).rounded() / 10_000
        let seed = "\(name)|\(rLat)|\(rLon)"
        var hash: UInt64 = 1469598103934665603 // FNV offset basis
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211 // FNV prime
        }
        let positive = hash & 0x7FFF_FFFF_FFFF_FFFF
        return Int64(bitPattern: positive | 0x2000_0000_0000_0000)
    }
}

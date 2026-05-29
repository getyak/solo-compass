import Foundation
import CoreLocation
import os

/// Protocol that lets tests inject a stub instead of hitting `CLGeocoder`.
@MainActor
public protocol ReverseGeocoding: AnyObject {
    func resolve(coordinate: CLLocationCoordinate2D) async -> ReverseGeocodeService.Resolved?
}

/// Wraps `CLGeocoder.reverseGeocodeLocation` and produces a slug-style
/// city code that's stable across runs. Used by Epic C US-C3 so the
/// city picker shows real names like "Hanoi" instead of synthetic
/// `osm_21.0_105.9`.
///
/// `@MainActor` because `CLGeocoder` is not Sendable in a thread-safe
/// way and we want the call site predictable. Apple rate-limits
/// reverse geocoding (50/min/app) — we let the OS handle that and just
/// surface failures as `nil`.
@MainActor
public final class ReverseGeocodeService: ReverseGeocoding {
    private static let logger = Logger(subsystem: "com.solocompass", category: "ReverseGeocodeService")

    public struct Resolved: Equatable, Sendable {
        public let cityCode: String       // slug like "vn-hanoi"
        public let name: String           // localized "Hanoi"
        public let countryCode: String    // ISO 3166-1 alpha-2 lowercase

        public init(cityCode: String, name: String, countryCode: String) {
            self.cityCode = cityCode
            self.name = name
            self.countryCode = countryCode
        }
    }

    private let geocoder: CLGeocoder

    public init(geocoder: CLGeocoder = CLGeocoder()) {
        self.geocoder = geocoder
    }

    /// Resolve a coordinate into a (cityCode, name, countryCode) tuple.
    /// Returns nil on geocoder failure / offline / rate-limit — callers
    /// must fall back to the synthetic `osm_<lat>_<lon>` cityCode.
    public func resolve(coordinate: CLLocationCoordinate2D) async -> Resolved? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            return Self.makeResolved(from: placemark)
        } catch {
            Self.logger.error("reverse geocode failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Static so the slug logic is unit-testable without a real geocoder.
    static func makeResolved(from placemark: CLPlacemark) -> Resolved? {
        // Locality (city) is the granularity we want; if missing fall
        // back to subAdministrativeArea (county) then administrativeArea
        // (state/province). We use whichever the country provides.
        let rawCity = placemark.locality
            ?? placemark.subAdministrativeArea
            ?? placemark.administrativeArea
        let rawCountry = placemark.isoCountryCode
        guard let cityName = rawCity, let country = rawCountry, !cityName.isEmpty, !country.isEmpty else {
            return nil
        }
        let countryCode = country.lowercased()
        let citySlug = slugify(cityName)
        guard !citySlug.isEmpty else { return nil }
        return Resolved(
            cityCode: "\(countryCode)-\(citySlug)",
            name: cityName,
            countryCode: countryCode
        )
    }

    /// Lowercase ASCII slug. Spaces → "-"; non-alphanumeric stripped.
    /// Diacritics folded so "México" becomes "mexico".
    static func slugify(_ raw: String) -> String {
        let folded = raw.folding(options: .diacriticInsensitive, locale: .init(identifier: "en"))
        var slug = ""
        var lastWasDash = false
        for scalar in folded.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                slug.append(Character(scalar))
                lastWasDash = false
            } else if !lastWasDash && !slug.isEmpty {
                slug.append("-")
                lastWasDash = true
            }
        }
        // Trim trailing dash.
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug
    }
}

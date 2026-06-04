import XCTest
import CoreLocation
import MapKit
@testable import SoloCompass

/// Guards the data contract behind 开始路线 → draw-on-map. `CompassMapContentView`
/// resolves a route's `experienceIds` to coordinates and only draws a connecting
/// `MapPolyline` when ≥2 resolve (single-stop routes just drop a pin). These tests
/// pin that the seeded routes actually resolve, so the map draw is reachable —
/// the original bug was that the Routes section was empty on a cold start, so the
/// CTA was never even tappable.
final class StartRouteCoordinateResolutionTests: XCTestCase {

    /// Every stop of every seed route resolves to a coordinate. A miss here means
    /// 开始路线 would silently no-op (the `coords.isEmpty` guard clears the route).
    func testEverySeedRouteStopResolvesToACoordinate() throws {
        let routes = try loadRoutes()
        let byId = try experiencesById()

        for route in routes {
            let coords = route.experienceIds.compactMap { byId[$0]?.coordinate }
            XCTAssertEqual(
                coords.count,
                route.experienceIds.count,
                "Route \(route.id.rawValue): \(coords.count)/\(route.experienceIds.count) stops resolved — unresolved stops break the map draw"
            )
            for c in coords {
                XCTAssertTrue(CLLocationCoordinate2DIsValid(c), "Resolved coordinate must be valid")
            }
        }
    }

    /// A multi-stop route (vientiane-monuments, 3 stops) resolves to ≥2 coordinates
    /// so the polyline branch (`active.coordinates.count >= 2`) actually fires, and
    /// the enclosing region has a finite, non-zero span (a 0/NaN span is what made
    /// the map render a 0×0 Metal layer → black screen).
    func testMultiStopRouteProducesDrawablePolylineAndRegion() throws {
        let routes = try loadRoutes()
        let byId = try experiencesById()

        let monuments = try XCTUnwrap(
            routes.first { $0.id.rawValue == "vientiane-monuments" },
            "vientiane-monuments seed route must exist"
        )
        let coords = monuments.experienceIds.compactMap { byId[$0]?.coordinate }
        XCTAssertGreaterThanOrEqual(coords.count, 2, "Polyline requires ≥2 resolved stops")

        let region = Self.region(enclosing: coords)
        XCTAssertTrue(region.span.latitudeDelta.isFinite && region.span.latitudeDelta > 0)
        XCTAssertTrue(region.span.longitudeDelta.isFinite && region.span.longitudeDelta > 0)
        XCTAssertTrue(CLLocationCoordinate2DIsValid(region.center))
        // Vientiane sits at ~17.96°N, 102.6°E — sanity-check the camera lands there.
        XCTAssertEqual(region.center.latitude, 17.96, accuracy: 0.2)
        XCTAssertEqual(region.center.longitude, 102.6, accuracy: 0.3)
    }

    /// A single-stop route (mekong-sunset) frames at the minimum span — centered
    /// on the lone pin at street level, not slammed all the way in. The polyline
    /// branch won't fire (only 1 coord), which is the intended "pin + fly" path.
    func testSingleStopRouteFramesAtMinimumSpan() throws {
        let routes = try loadRoutes()
        let byId = try experiencesById()

        let mekong = try XCTUnwrap(
            routes.first { $0.id.rawValue == "mekong-sunset" },
            "mekong-sunset seed route must exist"
        )
        let coords = mekong.experienceIds.compactMap { byId[$0]?.coordinate }
        XCTAssertEqual(coords.count, 1, "mekong-sunset is the single-stop seed route")

        let region = Self.region(enclosing: coords)
        XCTAssertEqual(region.span.latitudeDelta, Self.minRegionSpan, accuracy: 1e-9)
        XCTAssertEqual(region.span.longitudeDelta, Self.minRegionSpan, accuracy: 1e-9)
        XCTAssertEqual(region.center.latitude, coords[0].latitude, accuracy: 1e-9)
        XCTAssertEqual(region.center.longitude, coords[0].longitude, accuracy: 1e-9)
    }

    /// Partial resolution drops only the unresolvable stops (compactMap), so a
    /// route whose middle stop is missing still yields the resolvable ones — the
    /// polyline bridges the gap. This pins the count contract `startRouteOnMap`
    /// relies on (and that the os_log warning reports against).
    func testPartialResolutionKeepsOnlyResolvableStops() throws {
        let byId = try experiencesById()
        let known = try XCTUnwrap(byId["exp_vte_patuxai_view"]?.coordinate)
        let known2 = try XCTUnwrap(byId["exp_vte_pha_that_luang_dawn"]?.coordinate)

        let ids = ["exp_vte_patuxai_view", "exp_does_not_exist", "exp_vte_pha_that_luang_dawn"]
        let coords = ids.compactMap { byId[$0]?.coordinate }

        XCTAssertEqual(coords.count, 2, "Only the two resolvable stops survive compactMap")
        XCTAssertEqual(coords[0].latitude, known.latitude, accuracy: 1e-9)
        XCTAssertEqual(coords[1].latitude, known2.latitude, accuracy: 1e-9)
    }

    /// A route whose stops all fail to resolve yields no coordinates — the caller
    /// (`startRouteOnMap`) then clears `activeRoute` rather than drawing nothing.
    func testAllStopsUnresolvedYieldsNoCoordinates() throws {
        let byId = try experiencesById()
        let coords = ["nope_1", "nope_2"].compactMap { byId[$0]?.coordinate }
        XCTAssertTrue(coords.isEmpty)
    }

    // MARK: - Helpers

    /// Mirrors `CompassMapContentView.region(enclosing:)` (a private method) so the
    /// test exercises the same bounding-box + 30% padding math the map uses.
    private static func region(enclosing coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, Self.minRegionSpan),
            longitudeDelta: max((maxLon - minLon) * 1.3, Self.minRegionSpan)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// Mirrors `CompassMapContentView.minRegionSpan`.
    private static let minRegionSpan: CLLocationDegrees = 0.01

    private func loadRoutes() throws -> [Route] {
        let data = try Data(contentsOf: try url(for: "seed_routes"))
        return try JSONDecoder().decode([Route].self, from: data)
    }

    private func experiencesById() throws -> [String: Experience] {
        let data = try Data(contentsOf: try url(for: "seed_experiences"))
        let experiences = try JSONDecoder.iso8601Decoder.decode([Experience].self, from: data)
        return Dictionary(uniqueKeysWithValues: experiences.map { ($0.id, $0) })
    }

    private func url(for name: String) throws -> URL {
        let testBundle = Bundle(for: type(of: self))
        if let url = testBundle.url(forResource: name, withExtension: "json") { return url }
        if let url = Bundle.main.url(forResource: name, withExtension: "json") { return url }
        throw NSError(
            domain: "StartRouteCoordinateResolutionTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing bundled resource \(name).json"]
        )
    }
}

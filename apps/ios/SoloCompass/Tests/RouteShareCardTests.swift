import CoreLocation
import MapKit
import XCTest
@testable import SoloCompass

/// Covers the pure geometry + payload logic behind the route map/trace share
/// card: coordinate normalisation (aspect-preserved, y-flipped), bounding-rect
/// computation, and the fallback predicates that decide map → trace → gradient.
final class RouteShareCardTests: XCTestCase {

    // MARK: - Normalizer

    func test_normalize_empty_returnsEmpty() {
        XCTAssertTrue(RouteNormalizer.normalize([]).isEmpty)
    }

    func test_normalize_singlePoint_returnsCentred() {
        let pts = RouteNormalizer.normalize([.init(latitude: 13.7, longitude: 100.5)])
        XCTAssertEqual(pts.count, 1)
        XCTAssertEqual(pts[0].x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(pts[0].y, 0.5, accuracy: 0.0001)
    }

    func test_normalize_keepsAspectRatio_noStretch() {
        // A route 2° wide in lon but only 1° tall in lat must NOT fill the unit
        // square in both axes — the narrow axis is letterboxed (centred).
        let coords: [CLLocationCoordinate2D] = [
            .init(latitude: 10.0, longitude: 100.0), // SW
            .init(latitude: 11.0, longitude: 102.0), // NE
        ]
        let pts = RouteNormalizer.normalize(coords)
        // span = max(2, 1) = 2. lon maps 0..1 across the full width.
        XCTAssertEqual(pts[0].x, 0.0, accuracy: 0.0001)
        XCTAssertEqual(pts[1].x, 1.0, accuracy: 0.0001)
        // lat span 1 over span 2 → occupies middle half: 0.25 .. 0.75.
        XCTAssertEqual(pts[0].y, 0.25, accuracy: 0.0001)
        XCTAssertEqual(pts[1].y, 0.75, accuracy: 0.0001)
    }

    func test_points_flipsY_northIsUp() {
        // Higher latitude (north) must map to a SMALLER y (top of the rect).
        let coords: [CLLocationCoordinate2D] = [
            .init(latitude: 10.0, longitude: 100.0), // south
            .init(latitude: 11.0, longitude: 100.0), // north (degenerate lon)
        ]
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let pts = RouteNormalizer.points(in: rect, normalized: RouteNormalizer.normalize(coords), inset: 0)
        XCTAssertGreaterThan(pts[0].y, pts[1].y, "south stop should sit lower (larger y) than north stop")
    }

    func test_stopPoints_countMatchesInput() {
        let coords: [CLLocationCoordinate2D] = (0..<5).map {
            .init(latitude: 13.0 + Double($0) * 0.01, longitude: 100.0 + Double($0) * 0.01)
        }
        let rect = CGRect(x: 0, y: 0, width: 200, height: 360)
        XCTAssertEqual(RouteNormalizer.stopPoints(in: rect, coordinates: coords).count, 5)
    }

    // MARK: - Bounding map rect

    func test_boundingMapRect_empty_isNull() {
        XCTAssertTrue(RouteMapSnapshotter.boundingMapRect([]).isNull)
    }

    func test_boundingMapRect_containsAllStops() {
        let coords: [CLLocationCoordinate2D] = [
            .init(latitude: 13.74, longitude: 100.49),
            .init(latitude: 13.75, longitude: 100.51),
        ]
        let rect = RouteMapSnapshotter.boundingMapRect(coords)
        for c in coords {
            XCTAssertTrue(rect.contains(MKMapPoint(c)), "rect must contain every stop")
        }
    }

    func test_boundingMapRect_singlePoint_hasMinimumViewport() {
        let rect = RouteMapSnapshotter.boundingMapRect([.init(latitude: 13.74, longitude: 100.49)])
        XCTAssertGreaterThan(rect.size.width, 0, "single point must still get a non-zero viewport")
        XCTAssertGreaterThan(rect.size.height, 0)
    }

    // MARK: - Payload fallback predicates

    func test_payload_hasDrawableRoute_requiresTwoPoints() {
        XCTAssertFalse(makePayload(coords: []).hasDrawableRoute)
        XCTAssertFalse(makePayload(coords: [.init(latitude: 1, longitude: 1)]).hasDrawableRoute)
        XCTAssertTrue(makePayload(coords: [
            .init(latitude: 1, longitude: 1),
            .init(latitude: 2, longitude: 2),
        ]).hasDrawableRoute)
    }

    func test_payload_hasAnyCoordinate() {
        XCTAssertFalse(makePayload(coords: []).hasAnyCoordinate)
        XCTAssertTrue(makePayload(coords: [.init(latitude: 1, longitude: 1)]).hasAnyCoordinate)
    }

    // MARK: - Helpers

    private func makePayload(coords: [CLLocationCoordinate2D]) -> RouteSharePayload {
        RouteSharePayload(
            title: "Test Route",
            summary: "summary",
            placeLabel: "Bangkok",
            category: .coffee,
            durationMinutes: 90,
            distanceMeters: 1200,
            paceLabel: "Relaxed",
            stopCount: coords.count,
            walkedByCount: 0,
            tags: [],
            coordinates: coords
        )
    }
}

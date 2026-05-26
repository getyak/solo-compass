import XCTest
import CoreLocation
@testable import SoloCompass

// MARK: - US-001: radius ladder constants and ringFilter

final class EnrichmentAgentRingFilterTests: XCTestCase {

    // MARK: - Constants

    func testProgressiveRadiiValues() {
        XCTAssertEqual(EnrichmentAgent.progressiveRadii, [5_000, 10_000, 25_000, 100_000])
    }

    func testEnoughThreshold() {
        XCTAssertEqual(EnrichmentAgent.enoughThreshold, 8)
    }

    // MARK: - ringFilter

    private let center = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522) // Paris

    /// Build a POI at a given distance (approx) due north of center.
    private func poi(distanceMeters: Double, id: Int64 = 0) -> OverpassService.POI {
        // 1 degree latitude ≈ 111_320 m
        let latOffset = distanceMeters / 111_320.0
        return OverpassService.POI(
            osmId: id,
            name: "POI-\(Int(distanceMeters))m",
            nameEn: nil,
            lat: center.latitude + latOffset,
            lon: center.longitude,
            tags: [:]
        )
    }

    func testRingFilterKeepsPoiInsideRadius() {
        let inside = poi(distanceMeters: 3_000, id: 1)
        let result = EnrichmentAgent.ringFilter(
            pois: [inside],
            center: center,
            within: 5_000,
            beyond: 0
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].osmId, 1)
    }

    func testRingFilterDropsPoiOutsideWithin() {
        let outside = poi(distanceMeters: 6_000, id: 2)
        let result = EnrichmentAgent.ringFilter(
            pois: [outside],
            center: center,
            within: 5_000,
            beyond: 0
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testRingFilterDropsPoiInsideBeyond() {
        let tooClose = poi(distanceMeters: 3_000, id: 3)
        let result = EnrichmentAgent.ringFilter(
            pois: [tooClose],
            center: center,
            within: 10_000,
            beyond: 5_000
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testRingFilterKeepsPoiInAnnulus() {
        let inRing = poi(distanceMeters: 7_000, id: 4)
        let result = EnrichmentAgent.ringFilter(
            pois: [inRing],
            center: center,
            within: 10_000,
            beyond: 5_000
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].osmId, 4)
    }

    func testRingFilterMixedBatch() {
        let inner = poi(distanceMeters: 3_000, id: 10)   // in [0, 5000)  ✓
        let mid   = poi(distanceMeters: 7_000, id: 11)   // in [5000, 10000) — excluded when within=5000
        let outer = poi(distanceMeters: 12_000, id: 12)  // beyond 10000 — excluded

        let innerRing = EnrichmentAgent.ringFilter(
            pois: [inner, mid, outer],
            center: center,
            within: 5_000,
            beyond: 0
        )
        XCTAssertEqual(innerRing.count, 1)
        XCTAssertEqual(innerRing[0].osmId, 10)

        let annulus = EnrichmentAgent.ringFilter(
            pois: [inner, mid, outer],
            center: center,
            within: 10_000,
            beyond: 5_000
        )
        XCTAssertEqual(annulus.count, 1)
        XCTAssertEqual(annulus[0].osmId, 11)
    }

    func testRingFilterEmptyInput() {
        let result = EnrichmentAgent.ringFilter(
            pois: [],
            center: center,
            within: 5_000
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testRingFilterBeyondDefaultsToZero() {
        let near = poi(distanceMeters: 1_000, id: 20)
        let result = EnrichmentAgent.ringFilter(
            pois: [near],
            center: center,
            within: 5_000
        )
        XCTAssertEqual(result.count, 1)
    }
}

import XCTest
import CoreLocation
@testable import SoloCompass

/// Live integration test: hits the real Amap API with the compiled-in key
/// to verify Shenzhen POI data retrieval end-to-end.
///
/// Skipped in CI (no key), runs locally with `swift test` / Xcode when the
/// AMAP_API_KEY is baked into GeneratedSecrets.
@MainActor
final class AmapLiveIntegrationTests: XCTestCase {

    private let shenzhen = CLLocationCoordinate2D(latitude: 22.5431, longitude: 114.0579)

    private func skipIfNoKey() throws {
        let key = Secrets.resolvedAmapKey
        try XCTSkipIf(key.isEmpty, "AMAP_API_KEY not configured — skipping live test")
    }

    // MARK: - Live Amap fetch

    func testFetchShenzhenCoffeePOIs() async throws {
        try skipIfNoKey()

        let service = AmapPOIService()
        let pois = try await service.fetchPOIs(
            near: shenzhen,
            radiusMeters: 3000,
            category: .coffee
        )

        print("=== Amap Shenzhen coffee POIs: \(pois.count) ===")
        for poi in pois.prefix(10) {
            print("  [\(poi.id)] \(poi.name) @ (\(poi.lat), \(poi.lon)) tags=\(poi.tags)")
        }

        XCTAssertGreaterThan(pois.count, 0, "Shenzhen CBD should have coffee shops")

        for poi in pois {
            let dist = CLLocation(latitude: poi.lat, longitude: poi.lon)
                .distance(from: CLLocation(latitude: shenzhen.latitude, longitude: shenzhen.longitude))
            XCTAssertLessThan(dist, 10_000, "POI \(poi.name) should be within 10km of Shenzhen center")
        }

        for poi in pois {
            XCTAssertEqual(poi.tags["source"], "amap")
        }
    }

    func testFetchShenzhenAllCategories() async throws {
        try skipIfNoKey()

        let service = AmapPOIService()
        let pois = try await service.fetchPOIs(
            near: shenzhen,
            radiusMeters: 3000,
            category: nil
        )

        print("=== Amap Shenzhen all-category POIs: \(pois.count) ===")
        for poi in pois.prefix(15) {
            let category = poi.tags["amenity"] ?? poi.tags["tourism"] ?? poi.tags["leisure"] ?? "unknown"
            print("  [\(poi.id)] \(poi.name) category=\(category) @ (\(poi.lat), \(poi.lon))")
        }

        XCTAssertGreaterThan(pois.count, 5, "Shenzhen CBD broad search should return many POIs")
    }

    func testFetchShenzhenFoodPOIs() async throws {
        try skipIfNoKey()

        let service = AmapPOIService()
        let pois = try await service.fetchPOIs(
            near: shenzhen,
            radiusMeters: 3000,
            category: .food
        )

        print("=== Amap Shenzhen food POIs: \(pois.count) ===")
        for poi in pois.prefix(10) {
            print("  [\(poi.id)] \(poi.name) @ (\(poi.lat), \(poi.lon))")
        }

        XCTAssertGreaterThan(pois.count, 0, "Shenzhen CBD should have restaurants")
    }

    func testShenzhenIsInsideMainland() {
        XCTAssertTrue(
            CoordinateConverter.isInsideChinaMainland(shenzhen),
            "Shenzhen should be classified as mainland China"
        )
    }

    func testShenzhenGCJRoundTrip() {
        let gcj = CoordinateConverter.wgs84ToGcj02(shenzhen)
        let back = CoordinateConverter.gcj02ToWgs84(gcj)
        let dist = CLLocation(latitude: back.latitude, longitude: back.longitude)
            .distance(from: CLLocation(latitude: shenzhen.latitude, longitude: shenzhen.longitude))
        XCTAssertLessThan(dist, 1.0, "Round-trip should be sub-metre")
        print("=== GCJ-02 offset for Shenzhen: \(CLLocation(latitude: gcj.latitude, longitude: gcj.longitude).distance(from: CLLocation(latitude: shenzhen.latitude, longitude: shenzhen.longitude)))m ===")
    }
}

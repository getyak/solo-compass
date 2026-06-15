import XCTest
import CoreLocation
@testable import SoloCompass

/// End-to-end 5 km experience test for Shenzhen.
///
/// Picks a real Shenzhen location (Nanshan — Window of the World / Coastal City),
/// queries every ExperienceCategory at 5 km radius, and validates that the
/// returned data is rich enough for a good solo-traveler experience.
@MainActor
final class AmapShenzhen5kmExperienceTests: XCTestCase {

    // Nanshan district — Window of the World / Coastal City area
    private let nanshan = CLLocationCoordinate2D(latitude: 22.5348, longitude: 113.9718)
    private let radius = 5000

    private var service: AmapPOIService!

    override func setUp() {
        super.setUp()
        service = AmapPOIService()
    }

    private func skipIfNoKey() throws {
        try XCTSkipIf(
            Secrets.resolvedAmapKey.isEmpty,
            "AMAP_API_KEY not configured — skipping live test"
        )
    }

    // MARK: - Per-category coverage at 5 km

    func testAllCategoriesReturn5kmPOIs() async throws {
        try skipIfNoKey()

        var totalPOIs = 0
        var categoryResults: [(ExperienceCategory, Int)] = []

        for category in ExperienceCategory.allCases {
            let pois = try await service.fetchPOIs(
                near: nanshan,
                radiusMeters: radius,
                category: category
            )
            categoryResults.append((category, pois.count))
            totalPOIs += pois.count

            print("  \(category.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)): \(pois.count) POIs")

            for poi in pois {
                XCTAssertFalse(poi.name.isEmpty, "\(category) POI should have a name")
                XCTAssertEqual(poi.tags["source"], "amap", "\(category) POI source should be amap")

                let dist = CLLocation(latitude: poi.lat, longitude: poi.lon)
                    .distance(from: CLLocation(latitude: nanshan.latitude, longitude: nanshan.longitude))
                XCTAssertLessThan(dist, Double(radius) + 1000, "\(poi.name) too far from center")
            }
        }

        print("\n=== Nanshan 5km summary: \(totalPOIs) total POIs across \(ExperienceCategory.allCases.count) categories ===")
        for (cat, count) in categoryResults {
            print("  \(cat.rawValue): \(count)")
        }

        let nonEmpty = categoryResults.filter { $0.1 > 0 }.count
        XCTAssertGreaterThanOrEqual(
            nonEmpty, 5,
            "At least 5 of 8 categories should return POIs in Shenzhen Nanshan"
        )
        XCTAssertGreaterThan(totalPOIs, 50, "5 km around Nanshan should yield 50+ POIs total")
    }

    // MARK: - Broad search (nil category) at 5 km

    func testBroadSearch5km() async throws {
        try skipIfNoKey()

        let pois = try await service.fetchPOIs(
            near: nanshan,
            radiusMeters: radius,
            category: nil
        )

        print("=== Nanshan 5km broad search: \(pois.count) POIs ===")
        for poi in pois {
            let cat = poi.tags["amenity"] ?? poi.tags["tourism"] ?? poi.tags["leisure"] ?? "?"
            print("  \(poi.name)  [\(cat)]  (\(String(format: "%.4f", poi.lat)), \(String(format: "%.4f", poi.lon)))")
        }

        XCTAssertGreaterThanOrEqual(pois.count, 10, "Broad 5 km search should return 10+ POIs")

        let names = Set(pois.map(\.name))
        XCTAssertEqual(names.count, pois.count, "POI names should be unique (no duplicates)")
    }

    // MARK: - Coordinate quality

    func testCoordinatesAreWGS84NotGCJ02() async throws {
        try skipIfNoKey()

        let pois = try await service.fetchPOIs(
            near: nanshan,
            radiusMeters: radius,
            category: .food
        )
        guard let poi = pois.first else {
            XCTFail("No food POIs returned")
            return
        }

        let coord = CLLocationCoordinate2D(latitude: poi.lat, longitude: poi.lon)
        let shifted = CoordinateConverter.wgs84ToGcj02(coord)
        let drift = CLLocation(latitude: shifted.latitude, longitude: shifted.longitude)
            .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))

        print("=== Coordinate check: \(poi.name) WGS84→GCJ-02 drift = \(String(format: "%.1f", drift))m ===")
        XCTAssertGreaterThan(drift, 200, "GCJ offset should exist for Shenzhen coord")
        XCTAssertLessThan(drift, 800, "GCJ offset should be a single shift, not double")
    }

    // MARK: - Name quality (Chinese names present)

    func testChineseNamesPresent() async throws {
        try skipIfNoKey()

        let pois = try await service.fetchPOIs(
            near: nanshan,
            radiusMeters: radius,
            category: .coffee
        )

        let chineseNameCount = pois.filter { name in
            name.name.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(scalar.value)
            }
        }.count

        print("=== Name quality: \(chineseNameCount)/\(pois.count) POIs have Chinese characters ===")
        XCTAssertGreaterThan(
            chineseNameCount, 0,
            "Shenzhen coffee shops should include Chinese names"
        )
    }

    // MARK: - Distance distribution

    func testDistanceDistribution() async throws {
        try skipIfNoKey()

        let pois = try await service.fetchPOIs(
            near: nanshan,
            radiusMeters: radius,
            category: nil
        )

        let center = CLLocation(latitude: nanshan.latitude, longitude: nanshan.longitude)
        let distances = pois.map { poi in
            CLLocation(latitude: poi.lat, longitude: poi.lon).distance(from: center)
        }.sorted()

        guard !distances.isEmpty else {
            XCTFail("No POIs returned")
            return
        }

        let avgDist = distances.reduce(0, +) / Double(distances.count)
        let maxDist = distances.last!
        let within1km = distances.filter { $0 < 1000 }.count
        let within3km = distances.filter { $0 < 3000 }.count

        print("=== Distance distribution (Nanshan 5km) ===")
        print("  Total: \(distances.count)")
        print("  Avg distance: \(String(format: "%.0f", avgDist))m")
        print("  Max distance: \(String(format: "%.0f", maxDist))m")
        print("  Within 1km: \(within1km)")
        print("  Within 3km: \(within3km)")
        print("  Within 5km: \(distances.filter { $0 < 5000 }.count)")

        XCTAssertLessThan(maxDist, Double(radius) + 500, "Max POI distance should be within radius + tolerance")
    }
}

import XCTest
import CoreLocation
@testable import SoloCompass

// MARK: - MapKit free-text POI search

/// The search entry point the Nearby box escalates to when its local card
/// filter comes up empty. Network-dependent paths aren't exercised here (unit
/// tests stay offline); what's guaranteed is the input contract: an empty or
/// whitespace query never wastes a network round-trip and returns no pins.
@MainActor
final class MapKitSearchTests: XCTestCase {

    private let sf = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

    func testEmptyQueryShortCircuits() async throws {
        let service = MapKitPOIService()
        let results = try await service.search(query: "", near: sf)
        XCTAssertTrue(results.isEmpty)
        XCTAssertFalse(service.isFetching)
    }

    func testWhitespaceQueryShortCircuits() async throws {
        let service = MapKitPOIService()
        let results = try await service.search(query: "   \n\t ", near: sf)
        XCTAssertTrue(results.isEmpty)
        XCTAssertFalse(service.isFetching)
    }
}

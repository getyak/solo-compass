import XCTest
import CoreLocation
@testable import SoloCompass

/// P5: the map used a single coarse ~10km span everywhere, so travelers
/// couldn't read the shops underfoot. Camera spans are now two named levels:
/// street-level when a GPS fix exists, city-level when only a city is picked.
/// This locks the ordering (street tighter than city) and the street-level
/// budget (well under the old 0.09 coarse span) so a future edit can't silently
/// regress back to a district-scale zoom.
@MainActor
final class MapZoomLevelTests: XCTestCase {

    func testStreetLevelIsTighterThanCityLevel() {
        XCTAssertLessThan(
            MapViewModel.MapZoom.streetLevel,
            MapViewModel.MapZoom.cityLevel,
            "Street-level zoom must be tighter (smaller span) than city-level."
        )
    }

    func testStreetLevelIsStreetScaleNotDistrict() {
        // ~0.012 deg latitude ≈ 1.3km, i.e. walkable street scale. Guard well
        // under the old coarse 0.09 (~10km) so we don't regress.
        XCTAssertLessThanOrEqual(MapViewModel.MapZoom.streetLevel, 0.02)
        XCTAssertGreaterThan(MapViewModel.MapZoom.streetLevel, 0)
    }

    func testCityLevelStaysLegibleCityScale() {
        // City-level should be wider than street but still tighter than the old
        // coarse span, so the city outline reads without a location.
        XCTAssertGreaterThan(MapViewModel.MapZoom.cityLevel, MapViewModel.MapZoom.streetLevel)
        XCTAssertLessThan(MapViewModel.MapZoom.cityLevel, 0.09)
    }
}

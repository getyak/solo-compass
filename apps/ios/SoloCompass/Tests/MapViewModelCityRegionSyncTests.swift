import XCTest
import CoreLocation
import MapKit
@testable import SoloCompass

/// V-002 (US-014): the city header label and the map's rendered region must
/// always agree. `selectedCity` — whether set on cold start via a persisted
/// `lastSelectedCity` or switched at runtime — must drive `cameraPosition` to
/// the corresponding city center.
@MainActor
final class MapViewModelCityRegionSyncTests: XCTestCase {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "mapvm.cityregionsync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeViewModel(startingCity: String?) -> MapViewModel {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = startingCity
        return MapViewModel(
            locationService: LocationService(),
            experienceService: ExperienceService(),
            aiService: AIService(apiKey: ""),
            preferences: prefs
        )
    }

    private func distanceKm(
        _ center: CLLocationCoordinate2D,
        _ target: CLLocationCoordinate2D
    ) -> Double {
        let a = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let b = CLLocation(latitude: target.latitude, longitude: target.longitude)
        return a.distance(from: b) / 1000.0
    }

    /// Cold start with a persisted city slug lands the camera on that city,
    /// even though `didSet` does not fire for the `init`-time assignment.
    func testColdStartCameraMatchesSelectedCity() throws {
        let vm = makeViewModel(startingCity: "chiang-mai")
        XCTAssertEqual(vm.selectedCity, "chiang-mai")
        let region = try XCTUnwrap(vm.cameraPosition.region)
        let chiangMai = try XCTUnwrap(MapViewModel.knownCityCenters["chiang-mai"])
        XCTAssertLessThan(
            distanceKm(region.center, chiangMai), 1.0,
            "Cold-start camera must center on Chiang Mai within 1 km"
        )
    }

    /// Switching the city at runtime moves the camera to the new city.
    func testSwitchingCityMovesCamera() throws {
        let vm = makeViewModel(startingCity: "chiang-mai")
        let before = try XCTUnwrap(vm.cameraPosition.region).center

        vm.selectedCity = "san-francisco"

        let after = try XCTUnwrap(vm.cameraPosition.region).center
        XCTAssertGreaterThan(
            distanceKm(before, after), 100.0,
            "Switching from Chiang Mai to San Francisco must move the camera far"
        )
        let sf = try XCTUnwrap(MapViewModel.knownCityCenters["san-francisco"])
        XCTAssertLessThan(
            distanceKm(after, sf), 1.0,
            "Camera must center on San Francisco within 1 km after switching"
        )
    }
}

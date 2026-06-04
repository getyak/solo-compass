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
            aiService: AIService(),
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

    // MARK: - V-006: Vientiane (VTE) center resolution

    /// The seed code `VTE` must resolve to the authoritative Vientiane center
    /// (added in V-006). A cold start here previously fell through to the live
    /// centroid, which was empty during init → black screen.
    func testDefaultCenterForVTESeedCodeResolvesCatalog() throws {
        let vm = makeViewModel(startingCity: "VTE")
        let expected = try XCTUnwrap(MapViewModel.knownCityCenters["VTE"])
        XCTAssertLessThan(
            distanceKm(vm.defaultCenterForSelectedCity, expected), 0.1,
            "VTE must resolve to the catalog Vientiane center"
        )
        // ~17.96°N, 102.6°E — Vientiane proper.
        XCTAssertEqual(vm.defaultCenterForSelectedCity.latitude, 17.9757, accuracy: 0.05)
        XCTAssertEqual(vm.defaultCenterForSelectedCity.longitude, 102.6331, accuracy: 0.05)
    }

    /// The human slug `vientiane` resolves to the same center via the catalog's
    /// slug key (kept in lockstep with the `VTE` seed code).
    func testDefaultCenterForVientianeSlugResolvesCatalog() throws {
        let vm = makeViewModel(startingCity: "vientiane")
        let vte = try XCTUnwrap(MapViewModel.knownCityCenters["VTE"])
        XCTAssertLessThan(
            distanceKm(vm.defaultCenterForSelectedCity, vte), 0.1,
            "vientiane slug must resolve to the same center as the VTE seed code"
        )
    }

    /// A city the catalog doesn't cover and that has no seeded experiences falls
    /// back to the global default center rather than crashing or returning NaN.
    func testDefaultCenterForUnknownCityFallsBackToDefault() throws {
        let vm = makeViewModel(startingCity: "zzz-nonexistent")
        let center = vm.defaultCenterForSelectedCity
        XCTAssertTrue(CLLocationCoordinate2DIsValid(center))
        XCTAssertLessThan(
            distanceKm(center, MapViewModel.defaultCenter), 0.1,
            "Unknown, unseeded city must fall back to the default center"
        )
    }
}

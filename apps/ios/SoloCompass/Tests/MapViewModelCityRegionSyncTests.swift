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

    // MARK: - GPS city follow (cold start + locate button)

    /// V-007 (narrowed to its actual scenario): a city picked explicitly *in
    /// this session* — the user tapped it in the picker while GPS was still
    /// warming up — must survive the first GPS fix. Picking a SF/China city
    /// while physically in Laos must not snap the camera back to Laos.
    func testExplicitSessionPickSurvivesFirstGPSFix() throws {
        UserDefaults.standard.removeObject(forKey: "startCity")
        let locationService = LocationService()
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        let vm = MapViewModel(
            locationService: locationService,
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: prefs
        )
        // The user picks San Francisco through the picker BEFORE any fix lands.
        vm.selectCity("san-francisco")
        let sf = try XCTUnwrap(MapViewModel.knownCityCenters["san-francisco"])

        // Simulate the traveler being physically in Vientiane, Laos — ~12,000 km
        // from the picked San Francisco.
        let laos = CLLocationCoordinate2D(latitude: 17.9757, longitude: 102.6331)
        locationService.simulate(location: CLLocation(latitude: laos.latitude, longitude: laos.longitude))
        vm.bindToLocation()

        XCTAssertEqual(
            vm.autoExploreInvocationCount, 0,
            "An in-session pick's GPS fix must not run GPS-anchored auto-explore"
        )
        XCTAssertEqual(
            vm.selectedCity, "san-francisco",
            "A GPS fix must not change an explicit in-session city pick"
        )
        let region = try XCTUnwrap(vm.cameraPosition.region)
        XCTAssertLessThan(
            distanceKm(region.center, sf), 1.0,
            "Camera must stay on the picked city, not snap to the GPS location"
        )
        XCTAssertGreaterThan(
            distanceKm(region.center, laos), 1000.0,
            "Camera must NOT be anywhere near the real GPS location"
        )
    }

    /// The new cold-start rule: a city merely *persisted from a previous
    /// session* does NOT own the camera. Entering the app with the first GPS
    /// fix in Vientiane must land the map on the fix and flip the selection
    /// (the top-left pill) to Vientiane — where the traveler physically is.
    func testColdStartFollowsGPSCityOverPersistedCity() throws {
        UserDefaults.standard.removeObject(forKey: "startCity")
        let locationService = LocationService()
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = "san-francisco"
        let vm = MapViewModel(
            locationService: locationService,
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: prefs
        )
        XCTAssertEqual(vm.selectedCity, "san-francisco")

        let laos = CLLocationCoordinate2D(latitude: 17.9757, longitude: 102.6331)
        locationService.simulate(location: CLLocation(latitude: laos.latitude, longitude: laos.longitude))
        vm.bindToLocation()

        let selected = try XCTUnwrap(vm.selectedCity, "Cold start must adopt the GPS city")
        XCTAssertTrue(
            MapViewModel.cityCodeMatches("VTE", selected: selected),
            "Selection must flip to the GPS city (Vientiane), got \(selected)"
        )
        XCTAssertEqual(
            prefs.lastSelectedCity, selected,
            "The adopted GPS city must persist for the next cold start"
        )
        let region = try XCTUnwrap(vm.cameraPosition.region)
        XCTAssertLessThan(
            distanceKm(region.center, laos), 5.0,
            "Camera must center on the GPS fix, not the persisted city"
        )
    }

    /// The locate button (`recenterOnUser`) also adopts the GPS city: tapping
    /// it after wandering to another city must move the camera to the fix AND
    /// flip the pill/selection to the fix's city.
    func testRecenterOnUserAdoptsGPSCity() throws {
        UserDefaults.standard.removeObject(forKey: "startCity")
        let locationService = LocationService()
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = "chiang-mai"
        let vm = MapViewModel(
            locationService: locationService,
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: prefs
        )

        let shenzhen = CLLocationCoordinate2D(latitude: 22.5431, longitude: 114.0579)
        locationService.simulate(location: CLLocation(latitude: shenzhen.latitude, longitude: shenzhen.longitude))
        vm.recenterOnUser()

        let selected = try XCTUnwrap(vm.selectedCity, "Locate must adopt the GPS city")
        let selectedCenter = try XCTUnwrap(
            MapViewModel.knownCityCenters[selected],
            "Adopted city must resolve in the catalog, got \(selected)"
        )
        XCTAssertLessThan(
            distanceKm(selectedCenter, shenzhen), 5.0,
            "Adopted city must be Shenzhen, got \(selected)"
        )
        let region = try XCTUnwrap(vm.cameraPosition.region)
        XCTAssertLessThan(
            distanceKm(region.center, shenzhen), 1.0,
            "Camera must center on the GPS fix after tapping locate"
        )
    }

    /// A fix far from every known city (Beijing) drops to pure GPS-follow:
    /// selection cleared so the nearby query anchors on the fix, camera on the
    /// fix, and auto-explore left to discover + name the city.
    func testColdStartFarFromKnownCitiesDropsToGPSFollow() throws {
        UserDefaults.standard.removeObject(forKey: "startCity")
        let locationService = LocationService()
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = "chiang-mai"
        let vm = MapViewModel(
            locationService: locationService,
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: prefs
        )

        let beijing = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        locationService.simulate(location: CLLocation(latitude: beijing.latitude, longitude: beijing.longitude))
        vm.bindToLocation()

        XCTAssertNil(
            vm.selectedCity,
            "Far from every known city, the stale persisted selection must clear"
        )
        let region = try XCTUnwrap(vm.cameraPosition.region)
        XCTAssertLessThan(
            distanceKm(region.center, beijing), 5.0,
            "Camera must still center on the GPS fix"
        )
        XCTAssertEqual(
            vm.autoExploreInvocationCount, 1,
            "GPS-follow must hand the fix to auto-explore to discover the city"
        )
    }

    /// Foreground return with the process alive across a flight: the fix now
    /// resolves to another city → re-follow. Same city → leave pan/zoom alone.
    func testRefollowOnForegroundOnlyWhenCityChanged() throws {
        UserDefaults.standard.removeObject(forKey: "startCity")
        let locationService = LocationService()
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        let vm = MapViewModel(
            locationService: locationService,
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: prefs
        )
        // Cold start in Chiang Mai.
        let chiangMai = CLLocationCoordinate2D(latitude: 18.7877, longitude: 98.9938)
        locationService.simulate(location: CLLocation(latitude: chiangMai.latitude, longitude: chiangMai.longitude))
        vm.bindToLocation()
        let selectedAfterBind = try XCTUnwrap(vm.selectedCity)
        XCTAssertTrue(MapViewModel.cityCodeMatches("cmi", selected: selectedAfterBind))

        // Same-city foreground return: the user's pan must survive.
        let panTarget = CLLocationCoordinate2D(latitude: 18.9, longitude: 99.1)
        vm.cameraPosition = .region(MKCoordinateRegion(
            center: panTarget,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))
        vm.refollowUserCityIfMoved()
        let sameCityRegion = try XCTUnwrap(vm.cameraPosition.region)
        XCTAssertLessThan(
            distanceKm(sameCityRegion.center, panTarget), 1.0,
            "Foreground return in the same city must not move the camera"
        )

        // Flight to Shenzhen, then foreground return: must re-follow.
        let shenzhen = CLLocationCoordinate2D(latitude: 22.5431, longitude: 114.0579)
        locationService.simulate(location: CLLocation(latitude: shenzhen.latitude, longitude: shenzhen.longitude))
        vm.refollowUserCityIfMoved()
        let movedRegion = try XCTUnwrap(vm.cameraPosition.region)
        XCTAssertLessThan(
            distanceKm(movedRegion.center, shenzhen), 1.0,
            "Foreground return in a new city must recenter on the fix"
        )
        let selected = try XCTUnwrap(vm.selectedCity)
        let selectedCenter = try XCTUnwrap(MapViewModel.knownCityCenters[selected])
        XCTAssertLessThan(
            distanceKm(selectedCenter, shenzhen), 5.0,
            "Selection must flip to the new GPS city, got \(selected)"
        )
    }

    /// `recenter(on:)` must pin the camera exactly on the requested coordinate.
    /// Regression: the reload inside it used to run the pin auto-fit, which
    /// immediately dragged the camera back toward the nearest experience
    /// cluster — the user saw their location circle glide to screen center and
    /// slide away again on every locate tap.
    func testRecenterPinsCameraOnCoordinate() throws {
        let vm = makeViewModel(startingCity: "chiang-mai")
        // A wide settled span makes the Chiang Mai seed cluster "much tighter
        // than the camera", which is exactly the condition that used to
        // trigger the auto-fit yank.
        vm.currentSpanLatitudeDelta = 1.0

        // Recenter on a spot deliberately offset from the seed cluster.
        let target = CLLocationCoordinate2D(latitude: 18.75, longitude: 99.05)
        vm.recenter(on: target)

        let region = try XCTUnwrap(vm.cameraPosition.region)
        XCTAssertEqual(region.center.latitude, target.latitude, accuracy: 0.0001,
                       "Camera must stay pinned on the recenter coordinate")
        XCTAssertEqual(region.center.longitude, target.longitude, accuracy: 0.0001,
                       "Camera must stay pinned on the recenter coordinate")
        XCTAssertEqual(region.span.latitudeDelta, 0.04, accuracy: 0.0001,
                       "Recenter must keep its own span, not the auto-fit's")
    }

    /// Complement to the above: with NO city selected (pure GPS-follow mode), the
    /// first GPS fix SHOULD recenter the camera on the user — the auto-recenter
    /// path the fix must preserve.
    func testGPSFixRecentersWhenNoCitySelected() throws {
        let locationService = LocationService()
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = nil
        let vm = MapViewModel(
            locationService: locationService,
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: prefs
        )
        vm.selectedCity = nil

        let laos = CLLocationCoordinate2D(latitude: 17.9757, longitude: 102.6331)
        locationService.simulate(location: CLLocation(latitude: laos.latitude, longitude: laos.longitude))
        vm.bindToLocation()

        let region = try XCTUnwrap(vm.cameraPosition.region)
        XCTAssertLessThan(
            distanceKm(region.center, laos), 5.0,
            "With no city selected, the first GPS fix must recenter on the user"
        )
        // GPS-follow mode must still run auto-explore (the behavior the fix
        // preserves) — so a genuinely data-sparse landing still fetches places.
        XCTAssertEqual(
            vm.autoExploreInvocationCount, 1,
            "With no city selected, the GPS fix must still run auto-explore"
        )
    }
}

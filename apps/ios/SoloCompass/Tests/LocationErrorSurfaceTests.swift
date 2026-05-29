import XCTest
import CoreLocation
import SwiftData
@testable import SoloCompass

/// US-026: a GPS failure (`LocationService.lastError`) must surface as a
/// dismissible banner so the user understands why the map fell back to a
/// default region instead of their location. These tests pin the
/// `MapViewModel.locationErrorBannerText` derivation that the banner binds to.
@MainActor
final class LocationErrorSurfaceTests: XCTestCase {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "location.error.surface.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeViewModel() -> (MapViewModel, LocationService) {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        let repo = ExperienceRepository(
            context: ModelContext(SoloCompassModelContainer.makeInMemory()),
            preferences: nil
        )
        let service = ExperienceService(seed: [], repository: repo)
        let location = LocationService()
        let vm = MapViewModel(
            locationService: location,
            experienceService: service,
            aiService: AIService(),
            preferences: prefs
        )
        return (vm, location)
    }

    /// No error → no banner.
    func testNoErrorYieldsNoBanner() {
        let (vm, _) = makeViewModel()
        XCTAssertNil(vm.locationErrorBannerText, "banner must be absent when GPS is healthy")
    }

    /// `lastError` set → banner text is the localized copy.
    func testErrorYieldsLocalizedBanner() {
        let (vm, location) = makeViewModel()
        let denied = NSError(domain: kCLErrorDomain, code: CLError.denied.rawValue)
        location.simulate(error: denied)

        let expected = NSLocalizedString(
            "location.error.banner",
            comment: "Banner shown when GPS fails and the map falls back to a default region"
        )
        XCTAssertEqual(vm.locationErrorBannerText, expected,
            "banner must read the location.error.banner copy when lastError is set")
        XCTAssertNotEqual(expected, "location.error.banner",
            "the localized string must resolve, not fall through to the raw key")
    }
}

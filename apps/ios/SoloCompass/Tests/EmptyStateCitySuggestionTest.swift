import XCTest
import SwiftUI
import SwiftData
@testable import SoloCompass

final class EmptyStateCitySuggestionTest: XCTestCase {

    /// Loads the *complete bundled* `seed_experiences.json` into an isolated
    /// in-memory store with isolated preferences.
    ///
    /// These coverage checks must see exactly the shipped seed. Reading through
    /// `ExperienceService()` hit the shared persisted database, which earlier
    /// Explore tests had polluted with discovered `osm_*` city codes — that made
    /// this guard fail on a code the bundle never ships. The in-memory container
    /// never touches the shared store, so no simulator/database cleanup is needed.
    @MainActor
    private func isolatedSeedExperiences() -> [Experience] {
        let suite = "emptystate.seed.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            UserDefaults.standard.removeSuite(named: suite)
        }
        let container = SoloCompassModelContainer.makeInMemory()
        let repo = ExperienceRepository(
            context: ModelContext(container),
            preferences: UserPreferences(defaults: defaults)
        )
        _ = repo.importSeedIfNeeded()
        return repo.allExperiences()
    }

    @MainActor
    func testEmptySheetListViewWithCitySuggestion() throws {
        let view = EmptySheetListView(
            onExploreElsewhere: {},
            suggestedCityName: "Chiang Mai",
            onSwitchToSuggestedCity: {}
        )
        .frame(width: 390, height: 400)
        .environment(BestNowClock())

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        let image = renderer.uiImage
        XCTAssertNotNil(image, "EmptySheetListView should render")

        let path = "/tmp/empty_state_city_suggestion.png"
        if let data = image?.pngData() {
            try data.write(to: URL(fileURLWithPath: path))
            print("Wrote screenshot to \(path)")
        }
    }

    @MainActor
    func testEmptySheetListViewWithoutCitySuggestion() throws {
        let view = EmptySheetListView(
            onExploreElsewhere: {}
        )
        .frame(width: 390, height: 400)
        .environment(BestNowClock())

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        let image = renderer.uiImage
        XCTAssertNotNil(image, "EmptySheetListView should render without suggestion")

        let path = "/tmp/empty_state_no_suggestion.png"
        if let data = image?.pngData() {
            try data.write(to: URL(fileURLWithPath: path))
            print("Wrote screenshot to \(path)")
        }
    }

    @MainActor
    func testSuggestedCityNameLogic() throws {
        let allExps = isolatedSeedExperiences()
        XCTAssertFalse(allExps.isEmpty, "Seed data should have experiences")

        let cityCodes = Set(allExps.map { $0.location.cityCode })
        print("[TEST] allExperiences count: \(allExps.count)")
        print("[TEST] city codes: \(cityCodes)")
    }

    @MainActor
    func testCityCodeMatchesShenzhenAlias() {
        XCTAssertTrue(
            MapViewModel.cityCodeMatches("cn-深圳市", selected: "shenzhen"),
            "shenzhen should alias to cn-深圳市"
        )
        XCTAssertTrue(
            MapViewModel.cityCodeMatches("cn-深圳市", selected: "SZX"),
            "SZX should alias to cn-深圳市"
        )
        XCTAssertFalse(
            MapViewModel.cityCodeMatches("cmi", selected: "shenzhen"),
            "cmi should not match shenzhen"
        )
    }

    @MainActor
    func testCityNameMapCoversAllSeedCodes() {
        let allExps = isolatedSeedExperiences()
        let seedCodes = Set(allExps.map { $0.location.cityCode })

        // Guard against a silent fallback to the 2-city `hardcodedSeed`: assert
        // the loader actually produced every city shipped in the bundle, so the
        // `cityNameMap` sweep below isn't vacuously narrow.
        let bundledCities: Set<String> = [
            "cmi", "VTE", "cn-深圳市", "nyc", "tyo", "san-francisco", "sgn", "lis"
        ]
        XCTAssertTrue(
            bundledCities.isSubset(of: seedCodes),
            "expected the full bundled seed; missing "
                + "\(bundledCities.subtracting(seedCodes).sorted()); got \(seedCodes.sorted())"
        )

        // Assert against the real, now-`static` map — not a hand-copied subset.
        // The previous inline copy only listed 3 cities and silently rotted as
        // seeds gained sgn/nyc/lis/tyo/san-francisco; sourcing from the single
        // source of truth is what keeps this guard honest (and is only possible
        // now that `cityNameMap` is `static`).
        for code in seedCodes {
            XCTAssertNotNil(
                MapViewModel.cityNameMap[code],
                "MapViewModel.cityNameMap should have a name for seed code '\(code)'"
            )
        }
    }
}

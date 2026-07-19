import XCTest
import SwiftUI
@testable import SoloCompass

final class EmptyStateCitySuggestionTest: XCTestCase {

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
        let service = ExperienceService()
        let allExps = service.allExperiences
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
        let service = ExperienceService()
        let seedCodes = Set(service.allExperiences.map { $0.location.cityCode })
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

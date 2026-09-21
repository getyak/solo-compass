import XCTest
import CoreLocation
@testable import SoloCompass

@MainActor
final class POISearchOutcomeTests: XCTestCase {
    private func makeModel() -> MapViewModel {
        let defaults = UserDefaults(suiteName: "poi-search-\(UUID().uuidString)")!
        let preferences = UserPreferences(defaults: defaults)
        preferences.lastSelectedCity = "chiang-mai"
        return MapViewModel(locationService: LocationService(), experienceService: ExperienceService(), aiService: AIService(), preferences: preferences)
    }

    func testTransportFailureIsDifferentFromAnEmptyResultAndCanRetry() async {
        let model = makeModel()
        model.searchPOIsOverride = { _, _ in throw URLError(.notConnectedToInternet) }
        await model.webSearchPOIs(query: "  coffee  ", near: model.defaultCenterForSelectedCity)
        XCTAssertEqual(model.lastWebSearchResult, POISearchOutcome(query: "coffee", status: .failed))
        XCTAssertFalse(model.isSearchingWeb)
        model.searchPOIsOverride = { _, _ in [] }
        await model.webSearchPOIs(query: "coffee", near: model.defaultCenterForSelectedCity)
        XCTAssertEqual(model.lastWebSearchResult, POISearchOutcome(query: "coffee", status: .empty))
        XCTAssertFalse(model.isSearchingWeb)
    }

    func testCancelledSearchDoesNotReportNoResults() async {
        let model = makeModel()
        model.searchPOIsOverride = { _, _ in throw CancellationError() }
        await model.webSearchPOIs(query: "coffee", near: model.defaultCenterForSelectedCity)
        XCTAssertNil(model.lastWebSearchResult)
        XCTAssertFalse(model.isSearchingWeb)
    }

    func testChangingCityDiscardsOldSearchResponse() async {
        let model = makeModel()
        model.searchPOIsOverride = { _, _ in
            model.selectedCity = "san-francisco"
            return [OverpassService.POI(osmId: 923456789, name: "Stale city result", nameEn: nil, lat: 18.79, lon: 98.98, tags: [:])]
        }
        let added = await model.webSearchPOIs(query: "coffee", near: model.defaultCenterForSelectedCity)
        XCTAssertEqual(added, 0)
        XCTAssertNil(model.lastWebSearchResult)
        XCTAssertFalse(model.isSearchingWeb)
    }

    func testFeedbackOnlyMatchesTheQueryThatWasSearched() {
        let result = POISearchOutcome(query: "coffee", status: .empty)
        XCTAssertTrue(result.matches("  COFFEE\n"))
        XCTAssertFalse(result.matches("sunset"))
        XCTAssertFalse(result.matches(""))
    }
}

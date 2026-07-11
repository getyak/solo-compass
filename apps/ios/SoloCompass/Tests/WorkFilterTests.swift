import XCTest
import CoreLocation
import SwiftData
@testable import SoloCompass

/// "可办公 / Work-ready" map filter (the laptop pill) — the digital-nomad entry
/// point. `MapViewModel.isWorkFilter` keeps only places you can actually work
/// from, and is mutually exclusive with the category / custom-tag / Now / Saved
/// filters. The qualifying signal reuses the existing `.work` category and the
/// wifi/power `CategoryHighlight`s the enrichment pipeline already emits — no
/// new schema — so these tests pin both the pure predicate and the filter path.
@MainActor
final class WorkFilterTests: XCTestCase {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "work.filter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeExperience(
        id: String,
        cityCode: String,
        lon: Double,
        lat: Double,
        category: ExperienceCategory,
        highlights: [CategoryHighlight] = []
    ) -> Experience {
        let now = Date()
        return Experience(
            id: id,
            title: "Fixture \(id)",
            oneLiner: "Fixture \(id)",
            whyItMatters: "Work filter fixture",
            category: category,
            location: ExperienceLocation(coordinates: [lon, lat], cityCode: cityCode),
            bestTimes: [],
            durationMinutes: .init(min: 30, max: 60),
            howTo: [],
            realInconveniences: [],
            soloScore: SoloScore(
                overall: 5,
                breakdown: .init(
                    seatingFriendly: 7, soloPatronRatio: 7, staffPressure: 7,
                    soloPortioning: 7, ambianceFit: 7, safety: 7
                ),
                basedOnCount: 1
            ),
            sources: [InformationSource(type: .user, attribution: "test", verifiedAt: now)],
            confidence: Confidence(
                level: 3,
                lastVerifiedAt: now,
                reason: "Test fixture",
                signals: .init(aiScrapeAgeDays: 1, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .active,
            createdAt: now,
            updatedAt: now,
            categoryHighlights: highlights.isEmpty ? nil : highlights
        )
    }

    private func makeViewModel(seed: [Experience]) -> MapViewModel {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = "cmi"
        let service = ExperienceService(seed: seed)
        return MapViewModel(
            locationService: LocationService(),
            experienceService: service,
            aiService: AIService(),
            preferences: prefs
        )
    }

    // MARK: - Pure predicate

    func testWorkReadyTrueForWorkCategory() {
        let coworking = makeExperience(id: "w", cityCode: "cmi", lon: 98.99, lat: 18.78, category: .work)
        XCTAssertTrue(MapViewModel.isWorkReady(coworking),
                      "explicit .work spots (coworking, libraries) are always work-ready")
    }

    func testWorkReadyTrueForCafeWithWifi() {
        let cafe = makeExperience(
            id: "c", cityCode: "cmi", lon: 98.99, lat: 18.78, category: .coffee,
            highlights: [CategoryHighlight(kind: .wifi, label: "WiFi", value: "fast")]
        )
        XCTAssertTrue(MapViewModel.isWorkReady(cafe),
                      "a café that advertises wifi is somewhere you can sit and work")
    }

    func testWorkReadyTrueForCafeWithPower() {
        let cafe = makeExperience(
            id: "c", cityCode: "cmi", lon: 98.99, lat: 18.78, category: .coffee,
            highlights: [CategoryHighlight(kind: .power, label: "Outlets", value: "at seats")]
        )
        XCTAssertTrue(MapViewModel.isWorkReady(cafe),
                      "power at seats is enough to qualify a café")
    }

    func testWorkReadyFalseForPlainCafe() {
        let cafe = makeExperience(id: "c", cityCode: "cmi", lon: 98.99, lat: 18.78, category: .coffee)
        XCTAssertFalse(MapViewModel.isWorkReady(cafe),
                       "a café with no wifi/power signal is not work-ready — don't over-promise")
    }

    func testWorkReadyFalseForFood() {
        // Even a restaurant that happens to carry a wifi highlight isn't a work spot.
        let restaurant = makeExperience(
            id: "f", cityCode: "cmi", lon: 98.99, lat: 18.78, category: .food,
            highlights: [CategoryHighlight(kind: .wifi, label: "WiFi", value: "free")]
        )
        XCTAssertFalse(MapViewModel.isWorkReady(restaurant),
                       "only .work and wifi/power cafés qualify — food stays out")
    }

    // MARK: - Filtering end to end

    func testWorkFilterKeepsOnlyWorkReady() {
        let seed = [
            makeExperience(id: "coworking", cityCode: "cmi", lon: 98.9938, lat: 18.7877, category: .work),
            makeExperience(id: "wifi_cafe", cityCode: "cmi", lon: 98.9940, lat: 18.7880, category: .coffee,
                           highlights: [CategoryHighlight(kind: .wifi, label: "WiFi", value: "fast")]),
            makeExperience(id: "plain_cafe", cityCode: "cmi", lon: 98.9942, lat: 18.7882, category: .coffee),
            makeExperience(id: "restaurant", cityCode: "cmi", lon: 98.9944, lat: 18.7884, category: .food)
        ]
        let vm = makeViewModel(seed: seed)
        XCTAssertFalse(vm.isWorkFilter, "starts inactive")

        vm.selectWorkFilter()

        XCTAssertTrue(vm.isWorkFilter, "filter active after selecting")
        XCTAssertEqual(Set(vm.visibleExperiences.map(\.id)), ["coworking", "wifi_cafe"],
                       "only the coworking spot and the wifi café survive")
    }

    func testWorkFilterTogglesOff() {
        let seed = [
            makeExperience(id: "coworking", cityCode: "cmi", lon: 98.9938, lat: 18.7877, category: .work),
            makeExperience(id: "restaurant", cityCode: "cmi", lon: 98.9944, lat: 18.7884, category: .food)
        ]
        let vm = makeViewModel(seed: seed)
        let baseline = vm.visibleExperiences.count

        vm.selectWorkFilter()
        XCTAssertTrue(vm.isWorkFilter)

        vm.selectWorkFilter()
        XCTAssertFalse(vm.isWorkFilter, "re-tap toggles the filter off")
        XCTAssertEqual(vm.visibleExperiences.count, baseline,
                       "clearing restores the full nearby list")
    }

    // MARK: - Mutual exclusivity

    func testSelectingWorkClearsOtherFilters() {
        let seed = [makeExperience(id: "coworking", cityCode: "cmi", lon: 98.9938, lat: 18.7877, category: .work)]
        let vm = makeViewModel(seed: seed)
        vm.selectNowFilter()
        vm.selectFavoriteFilter()   // saved now active

        vm.selectWorkFilter()

        XCTAssertTrue(vm.isWorkFilter)
        XCTAssertNil(vm.selectedCategory, "category cleared when Work activates")
        XCTAssertFalse(vm.isNowFilter, "Now cleared when Work activates")
        XCTAssertFalse(vm.isFavoriteFilter, "Saved cleared when Work activates")
    }

    func testSelectingOtherFilterClearsWork() {
        let seed = [makeExperience(id: "coworking", cityCode: "cmi", lon: 98.9938, lat: 18.7877, category: .work)]
        let vm = makeViewModel(seed: seed)

        vm.selectWorkFilter()
        XCTAssertTrue(vm.isWorkFilter)
        vm.selectNowFilter()
        XCTAssertFalse(vm.isWorkFilter, "Now clears the Work filter")

        vm.selectWorkFilter()
        XCTAssertTrue(vm.isWorkFilter)
        vm.selectCategory(.food)
        XCTAssertFalse(vm.isWorkFilter, "category clears the Work filter")

        vm.selectWorkFilter()
        XCTAssertTrue(vm.isWorkFilter)
        vm.clearFilters()
        XCTAssertFalse(vm.isWorkFilter, "clearFilters clears the Work filter")
    }
}

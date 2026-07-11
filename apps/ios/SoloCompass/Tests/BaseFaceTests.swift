import XCTest
import CoreLocation
@testable import SoloCompass

/// 游民基地 (Base) logic layer: the face derivation that drives which content
/// the Base card/panel shows, and the work-ready predicate + ranking behind
/// its 「办公」section. Both are pure, so the truth tables pin them exactly.
@MainActor
final class BaseFaceTests: XCTestCase {

    // MARK: - Face derivation truth table

    func testPlanModeAlwaysPlanFace() {
        XCTAssertEqual(BaseFace.derive(mode: .plan, stage: nil), .plan)
        // Plan mode has no stage by construction, but even a stale stage value
        // must not flip the face — mode wins.
        XCTAssertEqual(BaseFace.derive(mode: .plan, stage: .live), .plan)
    }

    func testRecallModeAlwaysRecallFace() {
        XCTAssertEqual(BaseFace.derive(mode: .recall, stage: nil), .recall)
        XCTAssertEqual(BaseFace.derive(mode: .recall, stage: .leave), .recall)
    }

    func testLiveModeSplitsOnStage() {
        XCTAssertEqual(BaseFace.derive(mode: .live, stage: .land), .arrive,
                       "day 1 (land) reads as arriving — essentials first")
        XCTAssertEqual(BaseFace.derive(mode: .live, stage: .settle), .arrive,
                       "days 2–3 (settle) still read as arriving")
        XCTAssertEqual(BaseFace.derive(mode: .live, stage: .live), .live,
                       "day 4+ is the steady living face")
        XCTAssertEqual(BaseFace.derive(mode: .live, stage: .leave), .recall,
                       "leaving hands over to the recall loop")
    }

    func testLiveModeWithoutEntryDateRestsAtLiveFace() {
        // No confirmed entry date → no stage. The entry must still exist
        // (v1's inferred-entry lesson) and rest at the steady-state face.
        XCTAssertEqual(BaseFace.derive(mode: .live, stage: nil), .live)
    }

    // MARK: - Fixtures

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "base.face.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeExperience(
        id: String,
        cityCode: String = "cmi",
        category: ExperienceCategory,
        score: Double = 5,
        highlights: [CategoryHighlight] = []
    ) -> Experience {
        let now = Date()
        return Experience(
            id: id,
            title: "Fixture \(id)",
            oneLiner: "Fixture \(id)",
            whyItMatters: "Base fixture",
            category: category,
            location: ExperienceLocation(coordinates: [98.99, 18.78], cityCode: cityCode),
            bestTimes: [],
            durationMinutes: .init(min: 30, max: 60),
            howTo: [],
            realInconveniences: [],
            soloScore: SoloScore(
                overall: score,
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
        let vm = MapViewModel(
            locationService: LocationService(),
            experienceService: service,
            aiService: AIService(),
            preferences: prefs
        )
        vm.selectedCity = "cmi"
        return vm
    }

    // MARK: - isWorkReady truth table

    func testWorkReadyTrueForWorkCategory() {
        XCTAssertTrue(MapViewModel.isWorkReady(makeExperience(id: "w", category: .work)),
                      "explicit .work spots (coworking, libraries) are always work-ready")
    }

    func testWorkReadyTrueForCafeWithWifi() {
        let cafe = makeExperience(
            id: "c", category: .coffee,
            highlights: [CategoryHighlight(kind: .wifi, label: "WiFi", value: "fast")]
        )
        XCTAssertTrue(MapViewModel.isWorkReady(cafe),
                      "a café that advertises wifi is somewhere you can sit and work")
    }

    func testWorkReadyTrueForCafeWithPower() {
        let cafe = makeExperience(
            id: "c", category: .coffee,
            highlights: [CategoryHighlight(kind: .power, label: "Outlets", value: "at seats")]
        )
        XCTAssertTrue(MapViewModel.isWorkReady(cafe),
                      "power at seats is enough to qualify a café")
    }

    func testWorkReadyFalseForPlainCafe() {
        XCTAssertFalse(MapViewModel.isWorkReady(makeExperience(id: "c", category: .coffee)),
                       "a café with no wifi/power signal is not work-ready — don't over-promise")
    }

    func testWorkReadyFalseForFoodEvenWithWifi() {
        let restaurant = makeExperience(
            id: "f", category: .food,
            highlights: [CategoryHighlight(kind: .wifi, label: "WiFi", value: "free")]
        )
        XCTAssertFalse(MapViewModel.isWorkReady(restaurant),
                       "only .work and wifi/power cafés qualify — food stays out")
    }

    // MARK: - workReadySpots ranking

    func testWorkReadySpotsFiltersRanksAndLimits() {
        let seed = [
            makeExperience(id: "low_coworking", category: .work, score: 6.0),
            makeExperience(id: "top_cafe", category: .coffee, score: 9.0,
                           highlights: [CategoryHighlight(kind: .wifi, label: "WiFi", value: "fast")]),
            makeExperience(id: "mid_coworking", category: .work, score: 7.5),
            makeExperience(id: "plain_cafe", category: .coffee, score: 9.9),
            makeExperience(id: "restaurant", category: .food, score: 9.9),
            makeExperience(id: "other_city", cityCode: "bkk", category: .work, score: 9.9)
        ]
        let vm = makeViewModel(seed: seed)

        let top = vm.workReadySpots(limit: 2)
        XCTAssertEqual(top.map(\.id), ["top_cafe", "mid_coworking"],
                       "soloScore-descending, limited to 2 — plain café, restaurant, and other-city spots never qualify")

        let all = vm.workReadySpots(limit: 99)
        XCTAssertEqual(all.map(\.id), ["top_cafe", "mid_coworking", "low_coworking"])
    }

    func testWorkReadySpotsEmptyWithoutCity() {
        let vm = makeViewModel(seed: [makeExperience(id: "w", category: .work)])
        vm.selectedCity = nil
        XCTAssertTrue(vm.workReadySpots(limit: 3).isEmpty,
                      "no selected city → no spots (the panel hides the section)")
    }
}

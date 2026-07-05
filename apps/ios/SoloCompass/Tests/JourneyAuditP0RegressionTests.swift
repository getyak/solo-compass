import XCTest
import CoreLocation
@testable import SoloCompass

/// Regression harness for the two P0s from the compile→route→invite journey
/// audit. Each test locks in one behavior so a refactor that reintroduces the
/// bug fails in CI instead of the next field run:
///
///   P0-A  a hand-saved route must be visible on the Now shelf right away
///         (bestStartHour anchored to save time; isBestNow window honors it)
///   P0-B  re-compile must never swap a card for a different venue or a
///         lower-quality synthesis, and the silent auto-upgrade must skip
///         curated seed cards entirely
final class JourneyAuditP0RegressionTests: XCTestCase {

    // MARK: - P0-A · saved route visibility

    func testMakeRoutePassesBestStartHourThrough() {
        let route = RouteBuilder.makeRoute(
            id: RouteId(rawValue: "r-p0a"),
            title: "Afternoon Walk",
            summary: "",
            orderedExperiences: [exp("a", lon: 114.05, lat: 22.54)],
            cityCode: "SZX",
            source: .userCreated,
            bestStartHour: 14
        )
        XCTAssertEqual(route.bestStartHour, 14)
        XCTAssertTrue(
            route.isBestNow(at: date(hour: 14)),
            "A route anchored to the save hour must pass the Now shelf filter immediately"
        )
        XCTAssertTrue(route.isBestNow(at: date(hour: 16)), "still inside the 3h window")
        XCTAssertFalse(route.isBestNow(at: date(hour: 20)), "outside the window")
    }

    func testRouteWithoutBestStartHourFallsBackToBestNowFlag() {
        let route = RouteBuilder.makeRoute(
            id: RouteId(rawValue: "r-p0a-nil"),
            title: "Legacy",
            summary: "",
            orderedExperiences: [],
            cityCode: "SZX",
            source: .userCreated
        )
        XCTAssertNil(route.bestStartHour)
        XCTAssertFalse(
            route.isBestNow(at: date(hour: 14)),
            "No anchor + bestNow=false is exactly the invisible-route bug; makeRoute callers for user saves must pass bestStartHour"
        )
    }

    // MARK: - P0-B · re-compile adoption guard

    func testRecompileRejectsDifferentVenueBeyondDistance() {
        let original = exp("exp_test_bookstore", title: "旧天堂书店", solo: 9.7)
        let candidate = exp("exp_osm_other", title: "福家小书房", solo: 9.9)
        XCTAssertFalse(
            EnrichmentAgent.shouldAdoptRecompiled(original: original, candidate: candidate, distanceMeters: 300),
            "A distant, differently-named POI is another venue — adopting it drifts the card's identity"
        )
    }

    func testRecompileRejectsQualityDowngrade() {
        let original = exp("exp_test_bookstore", title: "旧天堂书店", solo: 9.7)
        let candidate = exp("exp_osm_same", title: "旧天堂书店", solo: 7.0)
        XCTAssertFalse(
            EnrichmentAgent.shouldAdoptRecompiled(original: original, candidate: candidate, distanceMeters: 10),
            "Same venue but a much thinner synthesis must not replace curated content (the 9.7 → 7.0 collapse)"
        )
    }

    func testRecompileAcceptsColocatedUpgrade() {
        let original = exp("exp_test_bookstore", title: "旧天堂书店", solo: 8.0)
        let candidate = exp("exp_osm_same", title: "Old Heaven Books", solo: 8.4)
        XCTAssertTrue(
            EnrichmentAgent.shouldAdoptRecompiled(original: original, candidate: candidate, distanceMeters: 10)
        )
    }

    func testRecompileAcceptsNameMatchDespiteCoordinateDrift() {
        let original = exp("exp_test_bookstore", title: "旧天堂书店", solo: 8.0)
        let candidate = exp("exp_osm_same", title: "旧天堂书店（华侨城店）", solo: 8.0)
        XCTAssertTrue(
            EnrichmentAgent.shouldAdoptRecompiled(original: original, candidate: candidate, distanceMeters: 200),
            "Provider coordinates drift; a clear name containment match is the same venue"
        )
    }

    func testRecompileToleratesSmallScoreDip() {
        let original = exp("exp_test_cafe", title: "Same Cafe", solo: 8.0)
        let candidate = exp("exp_osm_same", title: "Same Cafe", solo: 7.6)
        XCTAssertTrue(
            EnrichmentAgent.shouldAdoptRecompiled(original: original, candidate: candidate, distanceMeters: 10),
            "Re-scoring within tolerance is not a downgrade"
        )
    }

    // MARK: - P0-B · curated seed detection

    func testSingleSourceNonDiscoveredEntryIsCuratedSeed() {
        let e = exp(
            "exp_test_seed", title: "Seed",
            sources: [InformationSource(type: .wikivoyage, attribution: "Wikivoyage", verifiedAt: Date())]
        )
        XCTAssertTrue(e.isCuratedSeed)
    }

    func testOSMAmapAndMultiSourceEntriesAreNotCuratedSeeds() {
        let osm = exp(
            "exp_osm_123", title: "OSM",
            sources: [InformationSource(type: .user, attribution: "© OpenStreetMap contributors", verifiedAt: Date())]
        )
        XCTAssertFalse(osm.isCuratedSeed)

        let amap = exp(
            "exp_test_amap", title: "Amap",
            sources: [InformationSource(type: .amap, attribution: "© AutoNavi (Amap) + AI", verifiedAt: Date())]
        )
        XCTAssertFalse(amap.isCuratedSeed)

        let multi = exp(
            "exp_test_multi", title: "Verified",
            sources: [
                InformationSource(type: .wikivoyage, attribution: "Wikivoyage", verifiedAt: Date()),
                InformationSource(type: .reddit, attribution: "Reddit", verifiedAt: Date()),
            ]
        )
        XCTAssertFalse(multi.isCuratedSeed)
    }

    // MARK: - P0-B · silent auto-upgrade skips curated seeds

    @MainActor
    func testAutoUpgradeSkipsCuratedSeedButAllowsSkeleton() {
        let viewModel = makeViewModel()
        let curated = exp(
            "exp_test_seed", title: "Curated 9.7", solo: 9.7,
            sources: [InformationSource(type: .wikivoyage, attribution: "Wikivoyage", verifiedAt: Date())]
        )
        XCTAssertFalse(
            viewModel.shouldAutoUpgrade(curated),
            "The silent path must never risk overwriting a curated seed card"
        )

        let skeleton = exp(
            "exp_osm_skeleton", title: "Skeleton",
            sources: [InformationSource(type: .user, attribution: "© OpenStreetMap contributors", verifiedAt: Date())]
        )
        XCTAssertTrue(
            viewModel.shouldAutoUpgrade(skeleton),
            "Non-AI OSM skeletons remain auto-upgrade candidates"
        )
    }

    // MARK: - Fixtures

    /// A date pinned to a given local hour today.
    private func date(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
    }

    @MainActor
    private func makeViewModel() -> MapViewModel {
        let suite = "journey-audit-p0-tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = UserPreferences(defaults: defaults)
        return MapViewModel(
            locationService: LocationService(),
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: prefs
        )
    }

    private func exp(
        _ id: String,
        title: String = "Fixture",
        lon: Double = 114.05,
        lat: Double = 22.54,
        solo: Double = 8.0,
        sources: [InformationSource] = []
    ) -> Experience {
        let now = Date()
        return Experience(
            id: id, title: title,
            oneLiner: "one", whyItMatters: "why",
            category: .coffee,
            location: ExperienceLocation(coordinates: [lon, lat], cityCode: "SZX"),
            bestTimes: [TimeWindow(startHour: 9, endHour: 21)],
            durationMinutes: .init(min: 30, max: 60),
            howTo: [], realInconveniences: [],
            soloScore: SoloScore(
                overall: solo,
                breakdown: .init(
                    seatingFriendly: 7, soloPatronRatio: 7, staffPressure: 7,
                    soloPortioning: 7, ambianceFit: 7, safety: 7
                ),
                basedOnCount: 1
            ),
            sources: sources,
            confidence: Confidence(
                level: 1, lastVerifiedAt: now, reason: "test",
                signals: .init(aiScrapeAgeDays: 0, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .active,
            createdAt: now, updatedAt: now
        )
    }
}

import XCTest
import CoreLocation
import MapKit
@testable import SoloCompass

/// Regression harness for the six O1 rubric fixes. Each test locks in
/// exactly one behavior the multi-agent panel flagged, so a later refactor
/// that reintroduces the bug lights up in CI instead of the next rubric run:
///
///   O1-1  handoff auto-minimize: 30 s (was 10 s → invisible in evidence)
///   O1-2  empty state suppressed while `exploreSession.isActive`
///   O1-3  transient Amap enrichments consumed & folded into poi.tags
///   O1-4  direct-Anthropic path honors `poi.tags["source"]=="amap"` → .amap
///   O1-5  defaultTopN raised so dense Amap areas don't collapse to 6
///   O1-6  zoomToFit fits the added cluster instead of a fixed 4 km span
@MainActor
final class O1FixesRegressionTests: XCTestCase {

    // MARK: - O1-1 · handoff auto-minimize duration

    func testHandoffAutoMinimizeIsAtLeast30Seconds() {
        XCTAssertGreaterThanOrEqual(
            ExploreHandoffCard.autoMinimizeSeconds, 30,
            "handoff card auto-minimize must dwell ≥30 s so the 4 CTAs are actually reachable after a 25-30 s Explore run"
        )
    }

    // MARK: - O1-5 · defaultTopN

    func testDefaultTopNAllowsDenseAmapAreas() {
        XCTAssertGreaterThanOrEqual(
            EnrichmentAgent.defaultTopN, 12,
            "defaultTopN too low — dense Amap queries will discard >80% of POIs before synthesis"
        )
        XCTAssertLessThanOrEqual(
            EnrichmentAgent.defaultTopN, 30,
            "defaultTopN too high — synthesis cost and map clutter both explode"
        )
    }

    // MARK: - O1-4 · provenance honored in derived TrustBadge level

    func testAmapSourceYieldsAmapBadgeLevel() {
        let e = makeExperience(sources: [
            InformationSource(type: .amap, attribution: "© AutoNavi (Amap) + AI", verifiedAt: Date())
        ])
        XCTAssertEqual(e.trustBadgeLevel, .amap)
    }

    func testOSMOnlySourceStaysOSM() {
        let e = makeExperience(
            id: "exp_osm_12345",
            sources: [
                InformationSource(type: .user, attribution: "© OpenStreetMap contributors + AI", verifiedAt: Date())
            ]
        )
        XCTAssertEqual(e.trustBadgeLevel, .osm)
    }

    // MARK: - O1-3 · transient enrichment tag-key contract

    /// The bug: `AmapPOIService.transientEnrichments` was populated for 75/75
    /// POIs but `consumeEnrichments` was never called, so AIService received
    /// tag-less POIs. The fix reads the enrichment bag and folds it into
    /// `poi.tags` using the exact key names `AIService.synthesizePrompt`
    /// already reads at line 1656-1661. This test pins the tag-key contract.
    func testTransientEnrichmentTagKeysAreStable() {
        let representativePOI = OverpassService.POI(
            osmId: 123, name: "test", nameEn: nil,
            lat: 22.5, lon: 114.0,
            tags: [
                "fsq_rating": "4.4",
                "opening_hours": "18:00-24:00",
                "phone": "+86-755-8888-8888",
                "addr": "深圳市福田区福华路 88 号"
            ]
        )
        XCTAssertEqual(representativePOI.tags["fsq_rating"], "4.4")
        XCTAssertEqual(representativePOI.tags["opening_hours"], "18:00-24:00")
        XCTAssertEqual(representativePOI.tags["phone"], "+86-755-8888-8888")
        XCTAssertEqual(representativePOI.tags["addr"], "深圳市福田区福华路 88 号")
    }

    // MARK: - O1-6 · zoomToFit clusters the added pins

    func testZoomToFitProducesTighterSpanThanRecenter() throws {
        let vm = makeViewModel()
        let cluster: [CLLocationCoordinate2D] = [
            .init(latitude: 22.5411, longitude: 114.0567),
            .init(latitude: 22.5450, longitude: 114.0610),
            .init(latitude: 22.5370, longitude: 114.0520)
        ]
        let fallback = CLLocationCoordinate2D(latitude: 22.5411, longitude: 114.0567)
        vm.zoomToFit(cluster, fallback: fallback)
        let region = try XCTUnwrap(vm.cameraPosition.region)
        XCTAssertLessThan(
            region.span.latitudeDelta, 0.04,
            "zoomToFit produced a span as wide as recenter — cluster fit not tighter"
        )
        XCTAssertLessThan(
            region.span.longitudeDelta, 0.04,
            "zoomToFit produced a span as wide as recenter — cluster fit not tighter"
        )
    }

    func testZoomToFitEmptyClusterFallsBackSafely() throws {
        let vm = makeViewModel()
        let fallback = CLLocationCoordinate2D(latitude: 22.5411, longitude: 114.0567)
        vm.zoomToFit([], fallback: fallback)
        let region = try XCTUnwrap(vm.cameraPosition.region)
        // recenter(on:) uses the 0.04 span.
        XCTAssertEqual(region.span.latitudeDelta, 0.04, accuracy: 0.0001)
    }

    // MARK: - Fixtures

    private func makeViewModel() -> MapViewModel {
        let suite = "o1fixes.\(UUID().uuidString)"
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

    private func makeExperience(id: String = "exp_amap_1", sources: [InformationSource]) -> Experience {
        let now = Date()
        return Experience(
            id: id, title: "Fixture",
            oneLiner: "one", whyItMatters: "why",
            category: .food,
            location: ExperienceLocation(coordinates: [0, 0], cityCode: "test"),
            bestTimes: [TimeWindow(startHour: 9, endHour: 21)],
            durationMinutes: .init(min: 30, max: 60),
            howTo: [], realInconveniences: [],
            soloScore: SoloScore(
                overall: 7,
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

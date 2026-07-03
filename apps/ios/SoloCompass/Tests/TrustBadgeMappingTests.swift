import XCTest
@testable import SoloCompass

/// Guards the Experience → TrustBadge.Level mapping so provenance never
/// silently regresses to "curated" when a real source signal is present.
/// The mapping is the entire point of slice A — cross-source signals must
/// win over single-source labels, and Amap POIs must never be misread as
/// OSM once tagged.
final class TrustBadgeMappingTests: XCTestCase {

    // MARK: - Fixtures

    private func makeExperience(
        id: String = "exp_osm_1",
        sources: [InformationSource]
    ) -> Experience {
        let now = Date()
        return Experience(
            id: id,
            title: "Fixture",
            oneLiner: "one",
            whyItMatters: "why",
            category: .food,
            location: ExperienceLocation(coordinates: [0, 0], cityCode: "test"),
            bestTimes: [TimeWindow(startHour: 0, endHour: 23)],
            durationMinutes: .init(min: 30, max: 60),
            howTo: [],
            realInconveniences: [],
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
                level: 1,
                lastVerifiedAt: now,
                reason: "test",
                signals: .init(
                    aiScrapeAgeDays: 0, passiveGpsHits30d: 0,
                    activeReports30d: 0, trustedVerifications: 0
                )
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .active,
            createdAt: now,
            updatedAt: now
        )
    }

    private func src(_ t: InformationSource.SourceType) -> InformationSource {
        InformationSource(type: t, attribution: nil, verifiedAt: Date())
    }

    // MARK: - Mapping rules

    /// ≥2 distinct source types beats every single-source label.
    func testTwoDistinctSourcesYieldsVerified() {
        let e = makeExperience(id: "exp_osm_1", sources: [src(.amap), src(.user)])
        XCTAssertEqual(e.trustBadgeLevel, .verified(sourceCount: 2))
    }

    /// Three distinct sources should reflect the count exactly.
    func testThreeSourcesReportsCount() {
        let e = makeExperience(sources: [src(.amap), src(.wikipedia), src(.user)])
        XCTAssertEqual(e.trustBadgeLevel, .verified(sourceCount: 3))
    }

    /// Duplicates of the same source type collapse — not "verified".
    func testDuplicateSameTypeDoesNotUpgrade() {
        let e = makeExperience(id: "exp_osm_1", sources: [src(.amap), src(.amap)])
        XCTAssertEqual(e.trustBadgeLevel, .amap)
    }

    /// Amap-only surfaces `.amap` regardless of id prefix.
    func testAmapOnlyYieldsAmap() {
        let e = makeExperience(id: "exp_osm_42", sources: [src(.amap)])
        XCTAssertEqual(e.trustBadgeLevel, .amap)
    }

    /// User-created id prefix + no rich sources → `.userCreated`.
    /// (This is what happens for hand-registered places before AI fills it in.)
    func testUserCreatedIdPrefix() {
        let e = makeExperience(id: "exp_user_abc", sources: [src(.user)])
        XCTAssertEqual(e.trustBadgeLevel, .userCreated)
    }

    /// OSM id prefix + no amap in sources → `.osm`.
    /// This is the common overseas explore path (OSM base, .user attribution).
    func testOsmPrefixWithoutAmapYieldsOsm() {
        let e = makeExperience(id: "exp_osm_9", sources: [src(.user)])
        XCTAssertEqual(e.trustBadgeLevel, .osm)
    }

    /// Curated seed (non-osm, non-user id, no attribution) → `.curated`.
    func testCuratedFallback() {
        let e = makeExperience(id: "seed_paris_louvre", sources: [])
        XCTAssertEqual(e.trustBadgeLevel, .curated)
    }

    /// Amap flag wins over the OSM id prefix — the pipeline tags Amap-sourced
    /// POIs with `.amap` even though they share the `exp_osm_` id prefix.
    /// Regression guard: if this ever silently returns `.osm`, users on the
    /// mainland stop seeing that AutoNavi contributed.
    func testAmapFlagBeatsOsmIdPrefix() {
        let e = makeExperience(id: "exp_osm_amap_1", sources: [src(.amap)])
        XCTAssertEqual(e.trustBadgeLevel, .amap)
    }
}

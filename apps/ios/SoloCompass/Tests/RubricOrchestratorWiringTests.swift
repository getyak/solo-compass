import XCTest
import CoreLocation
@testable import SoloCompass

/// ④ Self-eval Rubric — orchestrator wiring test.
///
/// Sibling to `RubricTests` (pure value + scorer). Here we assert the
/// contract that the orchestrator exposes a `rubricStore` and that
/// records written to it flow through the public API. We don't drive
/// a full turn (would need AIService/network) — the store append path
/// through the public API is what matters and is exhaustively covered
/// here plus by RubricTests directly against the store.
@MainActor
final class RubricOrchestratorWiringTests: XCTestCase {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "rubric.wiring.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeExperience(id: String) -> Experience {
        let now = Date()
        return Experience(
            id: id,
            title: "Fixture \(id)",
            oneLiner: "Fixture \(id)",
            whyItMatters: "Rubric wiring fixture",
            category: .coffee,
            location: ExperienceLocation(coordinates: [114.05, 22.54], cityCode: "szx"),
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
            updatedAt: now
        )
    }

    private func makeOrchestrator() -> VoiceAgentOrchestrator {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = "szx"
        let vm = MapViewModel(
            locationService: LocationService(),
            experienceService: ExperienceService(seed: [makeExperience(id: "wiring_1")]),
            aiService: AIService(),
            preferences: prefs
        )
        return VoiceAgentOrchestrator(
            aiService: AIService(),
            voiceService: VoiceService(),
            mapViewModel: vm,
            preferences: prefs
        )
    }

    func testOrchestratorStartsWithEmptyRubricStore() {
        let orch = makeOrchestrator()
        XCTAssertTrue(orch.rubricStore.reports.isEmpty)
        XCTAssertNil(orch.rubricStore.latest)
    }

    func testRubricStoreAcceptsRecordThroughOrchestrator() {
        let orch = makeOrchestrator()
        let report = RubricReport(
            turnIndex: 7,
            relevance: 10, factuality: 10, conciseness: 10,
            contextUsage: 10, toolHonesty: 10, cardCoverage: 10
        )
        orch.rubricStore.record(report)
        XCTAssertEqual(orch.rubricStore.reports.count, 1)
        XCTAssertEqual(orch.rubricStore.latest?.turnIndex, 7)
        XCTAssertEqual(orch.rubricStore.latest?.overall, 100)
    }

    func testRollingAverageRisesWithBetterTurns() {
        let orch = makeOrchestrator()
        orch.rubricStore.record(RubricReport(
            turnIndex: 1,
            relevance: 4, factuality: 4, conciseness: 4,
            contextUsage: 4, toolHonesty: 4, cardCoverage: 4
        ))
        let before = orch.rubricStore.rollingOverall
        orch.rubricStore.record(RubricReport(
            turnIndex: 2,
            relevance: 10, factuality: 10, conciseness: 10,
            contextUsage: 10, toolHonesty: 10, cardCoverage: 10
        ))
        let after = orch.rubricStore.rollingOverall
        XCTAssertGreaterThan(after, before)
    }
}

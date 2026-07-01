import XCTest
import SwiftData
@testable import SoloCompass

/// Tests for `TasteUpdateService` (P1.2 #123).
///
/// The service has three contracts:
/// 1. Trigger every Nth visit (default 5, lowered to 1 in tests so they stay fast).
/// 2. Upsert exactly one `TasteProfile` row (singleton semantics).
/// 3. Confidence climbs from 0.30 to a 0.95 ceiling.
@MainActor
final class TasteUpdateServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration("TasteUpdateTests", isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: VisitRecord.self, TasteProfile.self,
            configurations: config
        )
    }

    private func makeService(triggerEvery: Int = 1) throws -> (TasteUpdateService, ModelContainer) {
        let container = try makeContainer()
        let svc = TasteUpdateService(aiService: AIService(), modelContainer: container)
        svc.triggerEvery = triggerEvery
        return (svc, container)
    }

    private func seedVisits(in container: ModelContainer, count: Int) throws {
        let ctx = ModelContext(container)
        for i in 0..<count {
            let v = VisitRecord(
                experienceId: "exp_taste_\(i)",
                visitedAt: Date(timeIntervalSince1970: TimeInterval(1_780_000_000 + i)),
                dwellSeconds: 600
            )
            ctx.insert(v)
        }
        try ctx.save()
    }

    private func fetchProfiles(in container: ModelContainer) throws -> [TasteProfile] {
        let ctx = ModelContext(container)
        return try ctx.fetch(FetchDescriptor<TasteProfile>())
    }

    // MARK: - Confidence curve

    func testConfidenceStartsAtFloor() throws {
        let (svc, _) = try makeService()
        XCTAssertEqual(svc.computedConfidence(visitCount: 0), 0.30, accuracy: 0.001)
    }

    func testConfidenceRisesLinearlyWithVisits() throws {
        let (svc, _) = try makeService()
        XCTAssertEqual(svc.computedConfidence(visitCount: 5), 0.55, accuracy: 0.001)
        XCTAssertEqual(svc.computedConfidence(visitCount: 10), 0.80, accuracy: 0.001)
    }

    func testConfidenceCeilingIs095() throws {
        let (svc, _) = try makeService()
        XCTAssertEqual(svc.computedConfidence(visitCount: 200), 0.95, accuracy: 0.001,
                       "even an over-active user must cap at the 0.95 ceiling")
    }

    // MARK: - Trigger cadence

    func testRecordVisitDoesNotPersistBeforeTrigger() async throws {
        let (svc, container) = try makeService(triggerEvery: 5)
        try seedVisits(in: container, count: 5)

        for _ in 0..<4 {
            await svc.recordVisitTriggered()
        }

        let profiles = try fetchProfiles(in: container)
        XCTAssertEqual(profiles.count, 0, "first 4 visits must not yet trigger a recompute (triggerEvery = 5)")
    }

    func testRecordVisitPersistsOnFifthCall() async throws {
        let (svc, container) = try makeService(triggerEvery: 5)
        try seedVisits(in: container, count: 5)

        for _ in 0..<5 {
            await svc.recordVisitTriggered()
        }

        let profiles = try fetchProfiles(in: container)
        XCTAssertEqual(profiles.count, 1, "the 5th visit must trigger a recompute and write exactly one row")
    }

    func testCounterResetsForTesting() async throws {
        let (svc, _) = try makeService(triggerEvery: 5)
        for _ in 0..<3 { await svc.recordVisitTriggered() }
        XCTAssertEqual(svc.triggerCountForTesting, 3)
        svc.resetForTesting()
        XCTAssertEqual(svc.triggerCountForTesting, 0)
    }

    // MARK: - Singleton enforcement

    func testRepeatedRecomputeStillProducesOneRow() async throws {
        let (svc, container) = try makeService(triggerEvery: 1)
        try seedVisits(in: container, count: 3)

        await svc.recordVisitTriggered() // visit 1
        await svc.recordVisitTriggered() // visit 2
        await svc.recordVisitTriggered() // visit 3

        let profiles = try fetchProfiles(in: container)
        XCTAssertEqual(profiles.count, 1, "TasteProfile is a singleton — repeated recomputes must upsert, not append")
    }

    func testRecomputeUpdatesConfidenceAsVisitsGrow() async throws {
        let (svc, container) = try makeService(triggerEvery: 1)

        try seedVisits(in: container, count: 2)
        await svc.recomputeProfile()
        let firstConfidence = try XCTUnwrap(fetchProfiles(in: container).first?.confidence)

        try seedVisits(in: container, count: 8) // total now 10
        await svc.recomputeProfile()
        let secondConfidence = try XCTUnwrap(fetchProfiles(in: container).first?.confidence)

        XCTAssertGreaterThan(secondConfidence, firstConfidence,
                             "adding more visits must monotonically increase confidence")
    }

    // MARK: - Embedding shape

    func testPersistedEmbeddingIs64Dim() async throws {
        let (svc, container) = try makeService(triggerEvery: 1)
        try seedVisits(in: container, count: 1)
        await svc.recordVisitTriggered()

        let profile = try XCTUnwrap(fetchProfiles(in: container).first)
        XCTAssertEqual(profile.embeddingVector.count, 64,
                       "persisted embedding must match the AIService contract dim")
    }

    // MARK: - Resilience

    func testMissingModelContainerDoesNotCrash() async {
        let svc = TasteUpdateService(aiService: AIService(), modelContainer: nil)
        svc.triggerEvery = 1
        await svc.recordVisitTriggered()
        XCTAssertTrue(true, "must not throw when there is no container attached")
    }
}

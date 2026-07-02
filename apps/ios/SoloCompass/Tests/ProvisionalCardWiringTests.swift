import XCTest
import CoreLocation
@testable import SoloCompass

/// ⑩ Card 可反悔性 — slice A wiring tests.
///
/// Sibling to `ProvisionalCardLedgerTests` (pure state machine): these
/// tests exercise the **orchestrator↔ledger contract**. Namely:
/// - a tool effect that would have pinned a card now goes through the ledger,
/// - the public `undoLastCard()` / `commitAllProvisionalCards()` surface
///   preserves the map correctly,
/// - `cardsByMessageId` remains the derived snapshot the chat view reads.
///
/// We can't easily drive the full tool call path without also spinning up
/// AIService, so the tests reach in via the internal `provisionalCards`
/// ledger to seed entries — same code path an `appendCard` would take.
@MainActor
final class ProvisionalCardWiringTests: XCTestCase {

    // MARK: - Helpers

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "provisional.wiring.\(UUID().uuidString)"
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
            whyItMatters: "Provisional wiring fixture",
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

    private final class Fixture {
        let orchestrator: VoiceAgentOrchestrator
        let vm: MapViewModel
        let prefs: UserPreferences
        init(orchestrator: VoiceAgentOrchestrator, vm: MapViewModel, prefs: UserPreferences) {
            self.orchestrator = orchestrator; self.vm = vm; self.prefs = prefs
        }
    }

    private func makeFixture() -> Fixture {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        prefs.lastSelectedCity = "szx"
        let vm = MapViewModel(
            locationService: LocationService(),
            experienceService: ExperienceService(seed: [makeExperience(id: "szx_1")]),
            aiService: AIService(),
            preferences: prefs
        )
        let orchestrator = VoiceAgentOrchestrator(
            aiService: AIService(),
            voiceService: VoiceService(),
            mapViewModel: vm,
            preferences: prefs
        )
        return Fixture(orchestrator: orchestrator, vm: vm, prefs: prefs)
    }

    private func exp(_ id: String) -> ChatCard {
        .experiences(id: UUID(), [makeExperience(id: id)])
    }

    // MARK: - Contract: initial map is empty

    func testFreshOrchestratorHasEmptyCardMap() {
        let f = makeFixture()
        XCTAssertTrue(f.orchestrator.cardsByMessageId.isEmpty)
        XCTAssertTrue(f.orchestrator.provisionalCards.entries.isEmpty)
    }

    // MARK: - Undo shrinks the visible map

    func testUndoLastCardHidesTheEntry() {
        let f = makeFixture()
        let msg = UUID()
        f.orchestrator.provisionalCards.append(card: exp("a"), to: msg, at: Date())
        // First one committed so it stays after the undo.
        f.orchestrator.commitAllProvisionalCards()
        f.orchestrator.provisionalCards.append(card: exp("b"), to: msg, at: Date())

        let before = f.orchestrator.provisionalCards.cardsByMessageId(at: Date())[msg]?.count ?? 0
        XCTAssertEqual(before, 2, "two visible entries before undo")

        let didUndo = f.orchestrator.undoLastCard()
        XCTAssertTrue(didUndo)
        XCTAssertEqual(f.orchestrator.cardsByMessageId[msg]?.count, 1,
                       "public snapshot must drop the undone card")
    }

    func testUndoLastCardReturnsFalseWhenAllCommitted() {
        let f = makeFixture()
        let msg = UUID()
        f.orchestrator.provisionalCards.append(card: exp("a"), to: msg, at: Date())
        f.orchestrator.commitAllProvisionalCards()

        XCTAssertFalse(f.orchestrator.undoLastCard(),
                       "undo must be a no-op once cards have committed")
        XCTAssertEqual(f.orchestrator.cardsByMessageId[msg]?.count, 1,
                       "committed card must remain visible")
    }

    // MARK: - Commit-all pins everything and preserves order

    func testCommitAllProvisionalCardsPinsEverything() {
        let f = makeFixture()
        let msg = UUID()
        f.orchestrator.provisionalCards.append(card: exp("a"), to: msg, at: Date())
        f.orchestrator.provisionalCards.append(card: exp("b"), to: msg, at: Date())

        f.orchestrator.commitAllProvisionalCards()

        XCTAssertEqual(f.orchestrator.cardsByMessageId[msg]?.count, 2)
        XCTAssertTrue(f.orchestrator.provisionalCards.entries.allSatisfy {
            $0.state == .committed
        }, "every entry must be committed after commitAllProvisionalCards()")
    }

    func testCommitAllDoesNotResurrectUndone() {
        let f = makeFixture()
        let msg = UUID()
        f.orchestrator.provisionalCards.append(card: exp("a"), to: msg, at: Date())
        _ = f.orchestrator.undoLastCard()

        f.orchestrator.commitAllProvisionalCards()

        XCTAssertTrue(f.orchestrator.cardsByMessageId.isEmpty,
                      "undone card must stay hidden even after commit-all")
    }

    // MARK: - Snapshot mirrors ledger projection

    func testCardsByMessageIdMatchesLedgerProjection() {
        let f = makeFixture()
        let msg = UUID()
        f.orchestrator.provisionalCards.append(card: exp("only"), to: msg, at: Date())
        f.orchestrator.commitAllProvisionalCards()

        let ledger = f.orchestrator.provisionalCards.cardsByMessageId(at: Date())
        XCTAssertEqual(f.orchestrator.cardsByMessageId[msg]?.count, ledger[msg]?.count)
    }
}

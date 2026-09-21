import XCTest
@testable import SoloCompass

/// Offline lifecycle guards for `VoiceAgentOrchestrator`: a scope/history
/// transition must mark the session not-ready *synchronously* (so an immediate
/// send is rejected instead of racing the reseed), and `stop()` must invalidate
/// any pending seed so a cold start→stop can't resurrect the old session.
///
/// Uses the DEBUG-only readiness seam and never makes a model call.
@MainActor
final class VoiceAgentOrchestratorLifecycleTests: XCTestCase {

    private func makeOrchestrator() -> VoiceAgentOrchestrator {
        VoiceAgentOrchestrator(
            aiService: AIService(),
            voiceService: VoiceService(),
            mapViewModel: MapViewModel(
                locationService: LocationService.shared,
                experienceService: ExperienceService(),
                aiService: AIService(),
                preferences: UserPreferences()
            ),
            preferences: UserPreferences()
        )
    }

    func testTimeoutSurfacesRetryableErrorAndRetainsMessages() {
        let orch = makeOrchestrator()
        orch.session.seedSystem("Test context")
        orch.session.beginUserTurn(transcript: "Find a quiet walk")
        let before = orch.session.messages
        XCTAssertFalse(orch.finishTurnIfTimedOut(elapsed: 1))
        XCTAssertTrue(orch.finishTurnIfTimedOut(elapsed: VoiceAgentSession.turnTimeoutSeconds + 1))
        XCTAssertTrue(orch.session.isEnded)
        XCTAssertEqual(orch.uiState, .error(.network))
        XCTAssertNotNil(orch.errorMessage)
        XCTAssertEqual(orch.session.messages, before)
    }

    func testCompactionRetainsFullVisibleAndRestoredTranscript() {
        let session = VoiceAgentSession()
        session.seedSystem("Context")
        for index in 0..<12 {
            session.beginUserTurn(transcript: "Question \(index)")
            session.appendAssistantTurn(content: "Reply \(index)", toolCalls: [])
            session.finishSpeakingTurn()
        }
        XCTAssertLessThanOrEqual(session.messages.count, VoiceAgentSession.messagesMaxCount)
        XCTAssertEqual(session.transcript.count, 24)
        XCTAssertEqual(session.transcript.first?.content, "Question 0")
        let transcript = session.transcript
        session.reseedSystem("Fresh context")
        XCTAssertTrue(session.transcript.isEmpty)
        session.restoreHistory(transcript)
        XCTAssertEqual(session.transcript, transcript)
        XCTAssertLessThanOrEqual(session.messages.count, VoiceAgentSession.messagesMaxCount)
    }

    func testRetryAfterTimeoutIsReadyAndRetainsConversation() {
        let orch = makeOrchestrator()
        orch.debug_setReadyForTesting(true)
        orch.session.seedSystem("Context")
        orch.session.beginUserTurn(transcript: "A quiet walk")
        let transcript = orch.session.transcript
        orch.finishTurnIfTimedOut(elapsed: VoiceAgentSession.turnTimeoutSeconds + 1)
        XCTAssertTrue(orch.restartIfNeeded())
        XCTAssertFalse(orch.session.isEnded)
        XCTAssertTrue(orch.debug_isSeeded)
        XCTAssertNil(orch.errorMessage)
        XCTAssertEqual(orch.session.transcript, transcript)
    }

    func testQuotaEndCannotBeRestartedAsNetworkRetry() {
        let orch = makeOrchestrator()
        orch.debug_setReadyForTesting(true)
        orch.session.end(reason: .quotaExceeded)
        XCTAssertFalse(orch.restartIfNeeded())
        XCTAssertTrue(orch.session.isEnded)
    }

    func testRebindContextMarksNotReadySynchronously() {
        let orch = makeOrchestrator()
        orch.debug_setReadyForTesting(true)
        XCTAssertTrue(orch.debug_isSeeded)
        let generationBefore = orch.debug_contextGeneration

        orch.rebindContext(nil)

        // Synchronous: the reseed Task has not run yet, but readiness is already
        // false and the context generation advanced.
        XCTAssertFalse(orch.debug_isSeeded)
        XCTAssertGreaterThan(orch.debug_contextGeneration, generationBefore)
        XCTAssertEqual(orch.handleTextInput("where should I read?"), .notReady)
    }

    func testRestoreConversationMarksNotReadySynchronously() {
        let orch = makeOrchestrator()
        orch.debug_setReadyForTesting(true)
        let generationBefore = orch.debug_contextGeneration

        orch.restoreConversation(id: "history-1", messages: [], scopedExperience: nil)

        XCTAssertFalse(orch.debug_isSeeded)
        XCTAssertGreaterThan(orch.debug_contextGeneration, generationBefore)
    }

    func testStopInvalidatesPendingSeed() {
        let orch = makeOrchestrator()
        orch.debug_setReadyForTesting(true)
        let generationBefore = orch.debug_contextGeneration

        orch.stop()

        XCTAssertFalse(orch.debug_isSeeded)
        XCTAssertGreaterThan(
            orch.debug_contextGeneration, generationBefore,
            "A stopped session must invalidate any in-flight seed completion"
        )
        XCTAssertEqual(orch.handleTextInput("hello?"), .notReady)
    }
}

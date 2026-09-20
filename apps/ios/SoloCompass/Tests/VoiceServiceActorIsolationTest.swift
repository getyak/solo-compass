import XCTest
@testable import SoloCompass

/// Story #US-011 — `VoiceService` is `@MainActor` isolated so callers (all
/// SwiftUI views / view models, which are themselves `@MainActor`) can send a
/// `VoiceService` value into a main-actor method and `await` its async API
/// without tripping the strict-concurrency "sending self.voiceService risks
/// data races" warning at ChatSheet.swift:621.
///
/// The permission cases below inject deterministic answers through the internal
/// `PermissionRequester` seam and invoke the REAL
/// `VoiceService.requestPermission()` implementation. Production keeps using
/// `VoiceService()` / `.live`, which prompts the real system APIs — so these
/// tests never touch the OS permission UI on a clean simulator.
@MainActor
final class VoiceServiceActorIsolationTest: XCTestCase {

    /// Constructing a `VoiceService` and touching its isolated state from a
    /// `@MainActor` context must be legal — no `await`/hop required for the
    /// synchronous, isolated members.
    func testVoiceServiceIsMainActorIsolated() {
        let voice = VoiceService()
        // Synchronous reads of main-actor-isolated state — these only compile
        // if `voice` is reachable on the current (main) actor.
        XCTAssertFalse(voice.isListening)
        XCTAssertEqual(voice.amplitude, 0)
    }

    // MARK: - Permission sequencing (real requestPermission() implementation)

    /// Both prompts granted: the awaited, main-actor-isolated call returns
    /// `true`, and both prompts were invoked exactly once, speech first.
    func testRequestPermissionBothGrantedReturnsTrue() async {
        XCTAssertTrue(Thread.isMainThread, "the @MainActor call site stays on the main thread")
        let calls = PermissionCallRecorder()
        let voice = VoiceService(permissions: PermissionRequester(
            requestSpeechAuthorization: {
                XCTAssertTrue(Thread.isMainThread, "speech permission request stays on the main actor")
                await calls.recordSpeech()
                return true
            },
            requestMicrophonePermission: {
                XCTAssertTrue(Thread.isMainThread, "microphone permission request stays on the main actor")
                await calls.recordMicrophone()
                return true
            }
        ))

        let granted = await voice.requestPermission()

        XCTAssertTrue(granted)
        let counts = await calls.counts
        XCTAssertEqual(counts.speech, 1, "speech authorization must be requested once")
        XCTAssertEqual(counts.microphone, 1, "microphone must be requested when speech is granted")
        XCTAssertEqual(counts.sequence, ["speech", "microphone"])
    }

    /// Speech denied: `requestPermission()` returns `false` and never reaches
    /// the microphone prompt.
    func testRequestPermissionSpeechDeniedSkipsMicrophone() async {
        let calls = PermissionCallRecorder()
        let voice = VoiceService(permissions: PermissionRequester(
            requestSpeechAuthorization: { await calls.recordSpeech(); return false },
            requestMicrophonePermission: { await calls.recordMicrophone(); return true }
        ))

        let granted = await voice.requestPermission()

        XCTAssertFalse(granted, "a speech denial must yield false")
        let counts = await calls.counts
        XCTAssertEqual(counts.speech, 1, "speech authorization must be requested once")
        XCTAssertEqual(counts.microphone, 0, "microphone must NOT be requested once speech is denied")
        XCTAssertEqual(counts.sequence, ["speech"])
    }

    /// Speech granted but microphone denied: `requestPermission()` returns
    /// `false` and both prompts were attempted, in order.
    func testRequestPermissionMicrophoneDeniedReturnsFalse() async {
        let calls = PermissionCallRecorder()
        let voice = VoiceService(permissions: PermissionRequester(
            requestSpeechAuthorization: { await calls.recordSpeech(); return true },
            requestMicrophonePermission: { await calls.recordMicrophone(); return false }
        ))

        let granted = await voice.requestPermission()

        XCTAssertFalse(granted, "a microphone denial must yield false")
        let counts = await calls.counts
        XCTAssertEqual(counts.speech, 1, "speech authorization must be requested once")
        XCTAssertEqual(counts.microphone, 1, "microphone must be requested after speech is granted")
        XCTAssertEqual(counts.sequence, ["speech", "microphone"])
    }
}

/// Thread-safe recorder of the injected permission requests and their order.
private actor PermissionCallRecorder {
    private var speechCalls = 0
    private var microphoneCalls = 0
    private var sequence: [String] = []

    func recordSpeech() {
        speechCalls += 1
        sequence.append("speech")
    }
    func recordMicrophone() {
        microphoneCalls += 1
        sequence.append("microphone")
    }

    var counts: (speech: Int, microphone: Int, sequence: [String]) {
        (speechCalls, microphoneCalls, sequence)
    }
}

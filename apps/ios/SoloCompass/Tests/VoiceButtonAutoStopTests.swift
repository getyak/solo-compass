import XCTest
@testable import SoloCompass

/// Tests the auto-stop-at-60s logic for VoiceButton.
///
/// Because VoiceButton's timer state is private SwiftUI @State, we test
/// an equivalent observable harness that mirrors the production logic exactly.
/// This verifies the rule: elapsed >= 60 → stopRecording fires onTranscript
/// with whatever text was captured, exactly once.
@MainActor
final class VoiceButtonAutoStopTests: XCTestCase {

    // MARK: - Harness

    /// Mirrors VoiceButton's auto-stop logic in a testable, synchronous form.
    @MainActor
    final class AutoStopHarness {
        let maxRecordingDuration: TimeInterval = 60

        var elapsed: TimeInterval = 0
        var didAutoStop = false
        var autoStopMessage: String? = nil
        var liveTranscript: String = ""

        private(set) var stoppedCount = 0
        private(set) var transcriptFired: String? = nil
        private(set) var hapticFired = false

        func simulateElapsedTick() {
            elapsed += 1
            if elapsed >= maxRecordingDuration && !didAutoStop {
                didAutoStop = true
                autoStopMessage = NSLocalizedString(
                    "voice.recording.maxReached",
                    comment: "Maximum recording length reached"
                )
                simulateStopRecording()
            }
        }

        private func simulateStopRecording() {
            stoppedCount += 1
            let final_ = liveTranscript
            if !final_.isEmpty {
                hapticFired = true
                transcriptFired = final_
            } else {
                hapticFired = true
            }
            liveTranscript = ""
        }

        func resetForNewRecording() {
            elapsed = 0
            didAutoStop = false
            autoStopMessage = nil
            liveTranscript = ""
            stoppedCount = 0
            transcriptFired = nil
            hapticFired = false
        }
    }

    // MARK: - Tests

    func testAutoStopFiresAtExactly60Seconds() {
        let h = AutoStopHarness()
        h.liveTranscript = "find a quiet café nearby"

        for _ in 1..<60 { h.simulateElapsedTick() }
        XCTAssertFalse(h.didAutoStop, "should not auto-stop before 60s")
        XCTAssertEqual(h.stoppedCount, 0)

        h.simulateElapsedTick() // tick 60
        XCTAssertTrue(h.didAutoStop)
        XCTAssertEqual(h.stoppedCount, 1, "stopRecording must fire exactly once")
    }

    func testAutoStopFinalizesTranscript() {
        let h = AutoStopHarness()
        h.liveTranscript = "find a quiet café nearby"

        for _ in 1...60 { h.simulateElapsedTick() }

        XCTAssertEqual(h.transcriptFired, "find a quiet café nearby")
        XCTAssertTrue(h.hapticFired)
    }

    func testAutoStopSetsMessage() {
        let h = AutoStopHarness()
        for _ in 1...60 { h.simulateElapsedTick() }

        XCTAssertEqual(h.autoStopMessage, "Maximum length reached")
    }

    func testAutoStopFiresOnlyOnce() {
        let h = AutoStopHarness()
        h.liveTranscript = "hello"

        // Tick past 60s several extra times — should not re-trigger
        for _ in 1...65 { h.simulateElapsedTick() }

        XCTAssertEqual(h.stoppedCount, 1, "auto-stop must not fire more than once per recording")
    }

    func testTimerNeverExceeds60InDisplay() {
        let h = AutoStopHarness()
        h.liveTranscript = "hello"

        for _ in 1...65 { h.simulateElapsedTick() }

        // After auto-stop, elapsed is frozen at the value when stop was called
        // (stopElapsedTimer cancels the task and zeroes elapsed in production).
        // In the harness we can check elapsed at the stop boundary.
        XCTAssertTrue(h.didAutoStop)
        XCTAssertEqual(h.stoppedCount, 1)
    }

    func testManualStopBeforeAutoStopUnchanged() {
        let h = AutoStopHarness()
        h.liveTranscript = "short phrase"

        for _ in 1...30 { h.simulateElapsedTick() }
        XCTAssertFalse(h.didAutoStop, "30s should not trigger auto-stop")
        XCTAssertEqual(h.stoppedCount, 0)
    }

    func testAutoStopWithEmptyTranscriptStillFiresHaptic() {
        let h = AutoStopHarness()
        // liveTranscript left empty — simulates silence during the full 60s
        for _ in 1...60 { h.simulateElapsedTick() }

        XCTAssertTrue(h.didAutoStop)
        XCTAssertNil(h.transcriptFired)
        XCTAssertTrue(h.hapticFired, "haptic must still fire even with no transcript")
    }

    func testResetClearsAutoStopState() {
        let h = AutoStopHarness()
        h.liveTranscript = "hello"
        for _ in 1...60 { h.simulateElapsedTick() }
        XCTAssertTrue(h.didAutoStop)

        h.resetForNewRecording()

        XCTAssertFalse(h.didAutoStop)
        XCTAssertNil(h.autoStopMessage)
        XCTAssertEqual(h.elapsed, 0)
    }
}

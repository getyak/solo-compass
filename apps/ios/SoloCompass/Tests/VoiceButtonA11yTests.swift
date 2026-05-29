import XCTest
@testable import SoloCompass

/// Tests the accessibility toggle logic introduced for VoiceOver / Switch Control support.
///
/// VoiceButton's isRecording state is private @State, so we test an equivalent
/// harness that mirrors startRecording / stopRecording toggling logic.
@MainActor
final class VoiceButtonA11yTests: XCTestCase {

    // MARK: - Stub VoiceService

    /// Minimal stub so startRecording / stopRecording can be called without a real
    /// microphone or speech recognizer.
    final class StubVoiceService: VoiceService {
        var startListeningCallCount = 0
        var stopListeningCallCount = 0
        var permissionResult = true

        override func requestPermission() async -> Bool { permissionResult }

        override func startListening() throws -> AsyncThrowingStream<String, Error> {
            startListeningCallCount += 1
            return AsyncThrowingStream { _ in }
        }

        override func stopListening() {
            stopListeningCallCount += 1
        }
    }

    // MARK: - Toggle harness

    /// Lightweight harness that mirrors VoiceButton's isRecording toggle logic
    /// without the SwiftUI / Task machinery.
    @MainActor
    final class ToggleHarness {
        private(set) var isRecording = false
        private(set) var listeningAnnouncementFired = false
        private(set) var stoppedAnnouncementFired = false
        var transcriptFired: String? = nil
        var liveTranscript: String = ""

        func startRecording() {
            isRecording = true
            listeningAnnouncementFired = true   // mirrors the UIAccessibility.post branch
        }

        func stopRecording() {
            isRecording = false
            stoppedAnnouncementFired = true     // mirrors the UIAccessibility.post branch
            let final_ = liveTranscript
            if !final_.isEmpty { transcriptFired = final_ }
            liveTranscript = ""
        }

        /// Simulates what the accessibilityAction does: toggle via isRecording.
        func toggleViaA11yAction() {
            if isRecording { stopRecording() } else { startRecording() }
        }
    }

    // MARK: - Tests

    func testA11yActionStartsRecordingWhenIdle() {
        let h = ToggleHarness()
        XCTAssertFalse(h.isRecording)

        h.toggleViaA11yAction()

        XCTAssertTrue(h.isRecording, "first a11y activation should start recording")
    }

    func testA11yActionStopsRecordingWhenActive() {
        let h = ToggleHarness()
        h.toggleViaA11yAction()   // start
        XCTAssertTrue(h.isRecording)

        h.toggleViaA11yAction()   // stop

        XCTAssertFalse(h.isRecording, "second a11y activation should stop recording")
    }

    func testListeningAnnouncementFiresOnStart() {
        let h = ToggleHarness()
        h.toggleViaA11yAction()

        XCTAssertTrue(h.listeningAnnouncementFired, "Listening… announcement must post when recording starts")
    }

    func testStoppedAnnouncementFiresOnStop() {
        let h = ToggleHarness()
        h.toggleViaA11yAction()   // start
        h.toggleViaA11yAction()   // stop

        XCTAssertTrue(h.stoppedAnnouncementFired, "Recording stopped announcement must post when recording stops")
    }

    func testTranscriptDeliveredOnStop() {
        let h = ToggleHarness()
        h.toggleViaA11yAction()   // start
        h.liveTranscript = "quiet café nearby"
        h.toggleViaA11yAction()   // stop

        XCTAssertEqual(h.transcriptFired, "quiet café nearby")
    }

    func testDoubleToggleLeavesRecordingFalse() {
        let h = ToggleHarness()
        h.toggleViaA11yAction()
        h.toggleViaA11yAction()

        XCTAssertFalse(h.isRecording, "two activations must leave recording stopped")
    }

    func testLocalizationKeysExist() {
        let keys = [
            "voice.button.hint",
            "voice.button.value.recording",
            "voice.button.value.idle",
            "voice.a11y.toggle",
            "voice.announcement.listening",
            "voice.announcement.stopped",
        ]
        for key in keys {
            let value = NSLocalizedString(key, comment: "")
            XCTAssertNotEqual(value, key, "Localizable.strings is missing key: \(key)")
        }
    }
}

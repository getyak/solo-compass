import XCTest
@testable import SoloCompass

final class VoiceButtonHapticTests: XCTestCase {

    // MARK: - shouldFireSpeechHaptic

    func testFiresWhenNotYetFiredAndTranscriptNonBlank() {
        XCTAssertTrue(VoiceButton.shouldFireSpeechHaptic(alreadyFired: false, transcript: "hello"))
    }

    func testDoesNotFireWhenAlreadyFired() {
        XCTAssertFalse(VoiceButton.shouldFireSpeechHaptic(alreadyFired: true, transcript: "hello"))
    }

    func testDoesNotFireWhenTranscriptIsEmpty() {
        XCTAssertFalse(VoiceButton.shouldFireSpeechHaptic(alreadyFired: false, transcript: ""))
    }

    func testDoesNotFireWhenTranscriptIsWhitespaceOnly() {
        XCTAssertFalse(VoiceButton.shouldFireSpeechHaptic(alreadyFired: false, transcript: "   "))
    }

    func testDoesNotFireWhenTranscriptIsTabAndNewline() {
        XCTAssertFalse(VoiceButton.shouldFireSpeechHaptic(alreadyFired: false, transcript: "\t\n"))
    }

    func testDoesNotFireWhenAlreadyFiredEvenIfTranscriptChanges() {
        XCTAssertFalse(VoiceButton.shouldFireSpeechHaptic(alreadyFired: true, transcript: "new words"))
    }

    func testFiresForSingleCharacterTranscript() {
        XCTAssertTrue(VoiceButton.shouldFireSpeechHaptic(alreadyFired: false, transcript: "a"))
    }

    func testFiresForTranscriptWithLeadingTrailingWhitespace() {
        XCTAssertTrue(VoiceButton.shouldFireSpeechHaptic(alreadyFired: false, transcript: "  word  "))
    }
}

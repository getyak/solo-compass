import XCTest
import Foundation
@testable import SoloCompass

/// US-027: A voice recording interruption (mic revoked mid-record, audio
/// session interruption, recognizer failure) must surface in the UI as a
/// dismissible toast instead of silently stopping. The live audio stream is
/// not drivable in a unit test, so we pin the pure toast-text derivation that
/// the `ChatSheet` banner binds to: feeding it a *throwing voice service's*
/// error must produce the localized `voice.interrupted` copy carrying that
/// error's description (mirrors how `VoiceProcessingToast` is tested).
@MainActor
final class VoiceInterruptionToastTest: XCTestCase {

    /// Stand-in for the voice service that always fails its stream, modeling
    /// the mic-revoked-mid-record path. We reuse the real `VoiceError` so the
    /// `errorDescription` we interpolate is exactly what production surfaces.
    private func throwingVoiceError() -> Error {
        let underlying = NSError(
            domain: "com.solocompass.voice",
            code: 561_017_449, // AVAudioSession interruption-style code
            userInfo: [NSLocalizedDescriptionKey: "Recording was interrupted"]
        )
        return VoiceService.VoiceError.recognitionFailed(underlying)
    }

    /// A throwing voice service's error produces a non-empty toast that is NOT
    /// the raw key (i.e. the localized format string actually resolved).
    func testInterruptionProducesLocalizedToast() {
        let toast = ChatSheet.voiceInterruptionToastText(for: throwingVoiceError())
        XCTAssertFalse(toast.isEmpty, "an interruption must surface a non-empty toast")
        XCTAssertNotEqual(
            toast, "voice.interrupted",
            "voice.interrupted must resolve to a real localized string, not the raw key"
        )
    }

    /// The toast embeds the underlying error's description so the user can see
    /// *why* recording stopped.
    func testToastContainsUnderlyingErrorDescription() {
        let error = throwingVoiceError()
        let toast = ChatSheet.voiceInterruptionToastText(for: error)
        XCTAssertTrue(
            toast.contains(error.localizedDescription),
            "toast must surface the underlying error description; got: \(toast)"
        )
    }

    /// The format string carries a `%@` placeholder so the error description is
    /// interpolated rather than appended — two different errors must yield two
    /// different toasts.
    func testToastVariesWithError() {
        let a = ChatSheet.voiceInterruptionToastText(
            for: NSError(domain: "a", code: 1, userInfo: [NSLocalizedDescriptionKey: "alpha failure"])
        )
        let b = ChatSheet.voiceInterruptionToastText(
            for: NSError(domain: "b", code: 2, userInfo: [NSLocalizedDescriptionKey: "beta failure"])
        )
        XCTAssertNotEqual(a, b, "the %@ placeholder must interpolate the specific error")
        XCTAssertTrue(a.contains("alpha failure"))
        XCTAssertTrue(b.contains("beta failure"))
    }

    /// The `voice.interrupted` key resolves in the bundle and keeps its `%@`
    /// placeholder (so StringsParity + format correctness both hold).
    func testLocalizationKeyResolvesWithPlaceholder() {
        let value = NSLocalizedString("voice.interrupted", comment: "")
        XCTAssertFalse(value.isEmpty)
        XCTAssertNotEqual(value, "voice.interrupted", "key must resolve to localized copy")
        XCTAssertTrue(value.contains("%@"), "voice.interrupted must keep its %@ placeholder")
    }
}

import XCTest
import SwiftUI
@testable import SoloCompass

/// US-008: The voice-processing toast must announce itself to VoiceOver. It
/// carries the `.updatesFrequently` accessibility trait so assistive
/// technologies treat it as live, frequently-updating content, and it posts a
/// `UIAccessibility` announcement on appear / text change (exercised manually
/// in the Simulator).
///
/// SwiftUI's view tree is opaque, so we reflect recursively over the resolved
/// `body` and assert that an `AccessibilityTraits` value somewhere in the tree
/// contains `.updatesFrequently`.
@MainActor
final class VoiceToastA11yTests: XCTestCase {

    func testToastViewTreeContainsUpdatesFrequentlyTrait() {
        let toast = VoiceProcessingToast(text: "Thinking about “coffee”…")
        XCTAssertTrue(
            Self.viewTree(toast.body, containsTrait: .updatesFrequently),
            "Active voice-processing toast must carry the .updatesFrequently "
                + "accessibility trait so VoiceOver announces its live updates"
        )
    }

    func testLocalizedTextTruncatesLongTranscript() {
        let long = String(repeating: "a", count: 200)
        let text = VoiceProcessingToast.localizedText(for: long)
        // The format string interpolates the truncated transcript; the result
        // must not contain the full 200-char input.
        XCTAssertFalse(text.contains(long), "transcript should be truncated")
        XCTAssertFalse(text.isEmpty)
    }

    func testVoiceProcessingLocalizationKeyResolves() {
        let value = NSLocalizedString("voice.processing", comment: "")
        XCTAssertFalse(value.isEmpty)
        XCTAssertNotEqual(
            value, "voice.processing",
            "voice.processing must resolve to a real localized string"
        )
    }

    // MARK: - Reflection helper

    /// Recursively walks the `Mirror` of a resolved SwiftUI view, returning
    /// `true` if any reachable `AccessibilityTraits` value contains `trait`.
    private static func viewTree(
        _ subject: Any,
        containsTrait trait: AccessibilityTraits,
        depth: Int = 0
    ) -> Bool {
        if let traits = subject as? AccessibilityTraits, traits.contains(trait) {
            return true
        }
        // Guard against pathological depth in the opaque modifier tree.
        guard depth < 60 else { return false }
        let mirror = Mirror(reflecting: subject)
        for child in mirror.children {
            if viewTree(child.value, containsTrait: trait, depth: depth + 1) {
                return true
            }
        }
        return false
    }
}

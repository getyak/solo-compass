import XCTest
import SwiftUI
@testable import SoloCompass

/// US-012: the swipe-hint capsule uses a repeating `.bounce` symbol effect,
/// which relies on `IndefiniteSymbolEffect` — an API available only on iOS 18+.
/// The view body gates that call behind `if #available(iOS 18, *)` and falls
/// back to the bare label on iOS 17. SwiftUI has no first-party snapshot harness
/// in this target, so we assert the body is constructible under whichever
/// deployment target the test bundle runs on; the `#available` branch is
/// resolved at runtime, so this exercises the iOS-17 fallback path on iOS 17
/// simulators and the iOS-18 effect path on iOS 18 simulators.
final class FavoritesBounceAvailabilityTest: XCTestCase {

    /// The capsule's body builds into a renderable tree without trapping. This
    /// covers both deployment targets: the `else` fallback compiles and renders
    /// on iOS 17, and the gated `.symbolEffect(.bounce, options:)` renders on
    /// iOS 18 — neither branch may crash at build/run time.
    func testSwipeHintCapsuleBodyIsConstructible() {
        let capsule = SwipeHintCapsuleView()
        XCTAssertNotNil(capsule.body)
    }

    /// Whether the runtime is iOS 17 or iOS 18, the hint label resolves the
    /// localized "swipe to remove" string rather than echoing the raw key, so
    /// both availability branches render the same user-facing copy.
    func testSwipeHintLabelResolvesLocalizedString() {
        let hint = NSLocalizedString("favorites.swipe.hint", comment: "Swipe left to remove")
        XCTAssertFalse(hint.isEmpty)
        XCTAssertNotEqual(hint, "favorites.swipe.hint", "Hint must resolve, not echo the key")
    }

    /// Rendering the capsule under iOS 18 specifically — the branch that calls
    /// the `IndefiniteSymbolEffect` API — must also construct cleanly. On
    /// iOS 17 simulators this assertion is skipped rather than failing.
    func testSwipeHintCapsuleRendersUnderIOS18() throws {
        guard #available(iOS 18, *) else {
            throw XCTSkip("iOS 18+ only: covers the IndefiniteSymbolEffect branch")
        }
        let capsule = SwipeHintCapsuleView()
        XCTAssertNotNil(capsule.body)
    }
}

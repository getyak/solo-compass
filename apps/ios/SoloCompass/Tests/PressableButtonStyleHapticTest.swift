import XCTest
@testable import SoloCompass

/// Source-level guard that `PressableButtonStyle` wires up haptic feedback
/// correctly and respects the accessibility Reduce Motion setting.
///
/// SwiftUI `ButtonStyle` bodies can't be exercised from XCTest without a full
/// host window, so — mirroring the sibling *TappableGuardTest pattern — we
/// scan the source file for the structural invariants that keep the haptic
/// behaviour correct and accessible.
final class PressableButtonStyleHapticTest: XCTestCase {

    private var source: String {
        get throws {
            let url = Self.sourceRoot()
                .appendingPathComponent("Views/Shared/PressableButtonStyle.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    /// Invariant 1: `Haptics.selection()` must still be wired in `makeBody` so
    /// opted-in surfaces (`haptic: true`) get their commit haptic.
    func testHapticsSelectionIsCalled() throws {
        XCTAssertTrue(
            try source.contains("Haptics.selection()"),
            "PressableButtonStyle must retain the `Haptics.selection()` call so "
                + "opt-in (`haptic: true`) surfaces still fire their commit haptic."
        )
    }

    /// Invariant 1b: the haptic must fire on *release/commit*, not press-down.
    /// A haptic on touch-down merely acknowledges a finger landing; the
    /// meaningful confirmation is that the action committed. Enforced by
    /// requiring the release-edge check `wasPressed && !isPressed`.
    func testHapticFiresOnReleaseNotPressDown() throws {
        XCTAssertTrue(
            try source.contains("wasPressed && !isPressed"),
            "PressableButtonStyle must gate the haptic on the release edge "
                + "(`wasPressed && !isPressed`) so it confirms the commit, not the press-down."
        )
    }

    /// Invariant 2: the call must be guarded by `accessibilityReduceMotion` so
    /// haptics are suppressed when the user has enabled Reduce Motion.
    func testReduceMotionGuardIsPresent() throws {
        XCTAssertTrue(
            try source.contains("accessibilityReduceMotion"),
            "PressableButtonStyle must read `accessibilityReduceMotion` and skip "
                + "the haptic when Reduce Motion is enabled."
        )
    }

    /// Invariant 3: the haptic call must be wrapped in a `#if canImport(UIKit)`
    /// guard so the style compiles on macOS / watchOS targets that lack UIKit.
    func testUIKitGuardIsPresent() throws {
        XCTAssertTrue(
            try source.contains("#if canImport(UIKit)"),
            "PressableButtonStyle must wrap `Haptics.selection()` in "
                + "`#if canImport(UIKit)` so the file compiles on non-UIKit platforms."
        )
    }

    /// Invariant 4: the `haptic` parameter must default to `false`. The audit
    /// found this style on ~34 buttons with only 2 opting out, so the app buzzed
    /// on essentially every button press — including plain navigation — which
    /// trains users to ignore haptics (HIG). Meaningful commit surfaces opt in
    /// explicitly with `haptic: true`; the default stays silent.
    func testHapticParameterDefaultsToFalse() throws {
        XCTAssertTrue(
            try source.contains("haptic: Bool = false"),
            "PressableButtonStyle.init must declare `haptic: Bool = false` so the "
                + "app doesn't buzz on every button press; commit surfaces opt in explicitly."
        )
    }

    // MARK: - Helpers

    /// `apps/ios/SoloCompass/` — derived from this test file's compile-time path
    /// (`…/SoloCompass/Tests/PressableButtonStyleHapticTest.swift`).
    private static func sourceRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // SoloCompass/
    }
}

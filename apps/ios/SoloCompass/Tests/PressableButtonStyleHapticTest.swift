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

    /// Invariant 1: `Haptics.selection()` must be called inside `makeBody` so
    /// every press-down fires a light selection haptic.
    func testHapticsSelectionIsCalled() throws {
        XCTAssertTrue(
            try source.contains("Haptics.selection()"),
            "PressableButtonStyle must call `Haptics.selection()` on press-down "
                + "to provide consistent tactile feedback across all tappable surfaces."
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

    /// Invariant 4: the `haptic` parameter must default to `true` so existing
    /// call sites gain haptic feedback without any modification.
    func testHapticParameterDefaultsToTrue() throws {
        XCTAssertTrue(
            try source.contains("haptic: Bool = true"),
            "PressableButtonStyle.init must declare `haptic: Bool = true` so "
                + "all existing call sites compile without modification."
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

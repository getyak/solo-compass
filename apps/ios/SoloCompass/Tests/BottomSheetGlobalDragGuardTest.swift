import XCTest
@testable import SoloCompass

/// Structural regression guard for the BottomInfoSheet's *global* drag.
///
/// History: the co-operative `contentDragGesture` (grab anywhere to steer the
/// sheet, Apple-Maps style) originally lived ONLY on the inner `ScrollView`.
/// At the `.peek` detent the summary card ("此刻最值得去") and its 带我去 / 换一个
/// buttons sit *above* that ScrollView (which is empty at peek), so the card
/// could only be *tapped* to expand — dragging its body, text, or buttons did
/// nothing. The user asked for the whole sheet to be pull-up-able from any
/// region, not just the handle.
///
/// The fix wraps everything BELOW the handle (peek header, peek card, sort
/// toolbar, and the list) in one container and attaches the drag there via
/// `.contentShape(Rectangle()).simultaneousGesture(contentDragGesture(…))`, so
/// a pull that begins anywhere in the body steers the sheet. The handle keeps
/// its own unconditional drag.
///
/// SwiftUI view trees can't be introspected from XCTest, so — like
/// `BottomSheetUnifiedScrollGuardTest` — this scans the source and asserts the
/// structural invariants that together prove the drag now covers the whole
/// body instead of just the scroll list.
final class BottomSheetGlobalDragGuardTest: XCTestCase {

    private func sheetSource() throws -> String {
        let url = Self.sourceRoot().appendingPathComponent("Views/Map/BottomInfoSheet.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Invariant: the `contentDragGesture` is attached to the container that
    /// ENCLOSES the ScrollView (so it also covers the peek card), NOT to the
    /// ScrollView itself. Proof: the ScrollView's last modifier
    /// (`.scrollBounceBehavior`) is followed by a closing brace `}` BEFORE the
    /// `.contentShape(Rectangle())` + `.simultaneousGesture(contentDragGesture(…))`
    /// pair — i.e. the scroll view closes and the gesture lands on the wrapper.
    func testContentDragGestureWrapsWholeBodyNotJustScrollView() throws {
        let source = try sheetSource()

        guard let bounceRange = source.range(of: ".scrollBounceBehavior(.basedOnSize)") else {
            XCTFail("Expected the unified ScrollView to end with .scrollBounceBehavior(.basedOnSize)")
            return
        }
        let afterBounce = source[bounceRange.upperBound...]

        guard let shapeRange = afterBounce.range(of: ".contentShape(Rectangle())") else {
            XCTFail(
                "Expected `.contentShape(Rectangle())` after the ScrollView so the peek "
                    + "whitespace is grabbable — the drag must cover the whole sheet body."
            )
            return
        }
        // The scroll view must CLOSE (a `}`) between its last modifier and the
        // drag-gesture attachment: that brace is the inner wrapping VStack /
        // ScrollView boundary, proving the gesture is on the enclosing body
        // container (which holds the peek card), not on the ScrollView.
        let betweenBounceAndShape = afterBounce[..<shapeRange.lowerBound]
        XCTAssertTrue(
            betweenBounceAndShape.contains("}"),
            "The drag gesture must be attached to the container ENCLOSING the ScrollView "
                + "(a `}` must close the scroll layer before `.contentShape`), so a pull on "
                + "the peek card — not just the list — steers the sheet."
        )

        // …and immediately after the contentShape, the co-operative drag is wired.
        let afterShape = afterBounce[shapeRange.upperBound...]
        guard let gestureRange = afterShape.range(of: ".simultaneousGesture(") else {
            XCTFail("Expected `.simultaneousGesture(` right after `.contentShape(Rectangle())`")
            return
        }
        let afterGesture = afterShape[gestureRange.upperBound...]
        XCTAssertTrue(
            afterGesture.hasPrefix("\n") && afterShape[gestureRange.upperBound...].contains("contentDragGesture("),
            "The body-level `.simultaneousGesture` must drive `contentDragGesture(…)` — the "
                + "same co-operative drag that decides steer-sheet vs. scroll-list per drag."
        )
    }

    /// Invariant: the handle keeps its OWN drag gesture (unconditional steer),
    /// separate from the body's co-operative one, so grabbing the handle always
    /// moves the sheet even when the list is scrolled at `.full`.
    func testHandleRetainsItsOwnDragGesture() throws {
        let source = try sheetSource()
        guard let handleRange = source.range(of: "private func dragHandleArea(") else {
            XCTFail("Could not locate `dragHandleArea` to scan")
            return
        }
        let afterHandle = source[handleRange.upperBound...]
        // Bound the scan to the handle function (up to the next top-level MARK).
        let handleBody: Substring
        if let nextMark = afterHandle.range(of: "\n// MARK:") {
            handleBody = afterHandle[..<nextMark.lowerBound]
        } else {
            handleBody = afterHandle
        }
        XCTAssertTrue(
            handleBody.contains("DragGesture(minimumDistance: 4)"),
            "The handle must keep its dedicated DragGesture so it always steers the sheet."
        )
    }

    // MARK: - Helpers

    /// `apps/ios/SoloCompass/` — derived from this test file's compile-time path.
    private static func sourceRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // SoloCompass/
    }
}

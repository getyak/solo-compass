import XCTest
import SwiftUI
@testable import SoloCompass

/// US-006: BottomInfoSheet drag handle hit target is at least 44 pt in
/// either dimension per Apple HIG so VoiceOver / Switch Control users can
/// reliably grab the handle and cycle detent levels.
///
/// `BottomInfoSheet.dragHandleArea` wraps a visually small 36×4 pill in a
/// `.frame(minWidth: 60, minHeight: 44).contentShape(Rectangle())` so the
/// tap region expands to the HIG minimum without altering the visual pill.
@MainActor
final class BottomInfoSheetHandleHitTargetTests: XCTestCase {

    func testHandleHitTargetHeightIsAtLeast44Points() {
        XCTAssertGreaterThanOrEqual(
            BottomSheetMetrics.handleHitTargetHeight,
            44,
            "Apple HIG requires interactive controls to be at least 44 pt tall"
        )
    }

    func testHandleHitTargetWidthIsAtLeast44Points() {
        XCTAssertGreaterThanOrEqual(
            BottomSheetMetrics.handleHitTargetWidth,
            44,
            "Drag handle hit area must be at least 44 pt wide"
        )
    }

    /// The hit area must satisfy ≥44 pt in *either* dimension; here it is
    /// generous in both (60×44).
    func testHitAreaFrameIsAtLeast44InEitherDimension() {
        let hitBox = CGRect(
            x: 0,
            y: 0,
            width: BottomSheetMetrics.handleHitTargetWidth,
            height: BottomSheetMetrics.handleHitTargetHeight
        )
        XCTAssertTrue(
            hitBox.width >= 44 || hitBox.height >= 44,
            "hit area \(hitBox.size) must be ≥44 pt in at least one dimension"
        )
    }

    // MARK: - Adjustable action: detent ladder

    func testIncrementCyclesPeekToMidToFull() {
        XCTAssertEqual(BottomSheetDetent.peek.nextHigher, .mid)
        XCTAssertEqual(BottomSheetDetent.mid.nextHigher, .full)
    }

    func testIncrementClampsAtFull() {
        XCTAssertEqual(BottomSheetDetent.full.nextHigher, .full)
    }

    func testDecrementCyclesFullToMidToPeek() {
        XCTAssertEqual(BottomSheetDetent.full.nextLower, .mid)
        XCTAssertEqual(BottomSheetDetent.mid.nextLower, .peek)
    }

    func testDecrementClampsAtPeek() {
        XCTAssertEqual(BottomSheetDetent.peek.nextLower, .peek)
    }

    // MARK: - Localization key presence

    func testSheetHandleLocalizationKeyResolves() {
        let value = NSLocalizedString("sheet.handle", comment: "")
        XCTAssertFalse(value.isEmpty)
        XCTAssertNotEqual(value, "sheet.handle", "sheet.handle must resolve to a real string")
    }
}

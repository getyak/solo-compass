import XCTest
@testable import SoloCompass

/// Structural regression guard for the *tappability* of `CreateRouteEntryCard`
/// — the dashed "創建你自己的路線" entry that sits between the Routes and Nearby
/// sections inside the BottomInfoSheet.
///
/// History: the card wrapped its `Button` in a press-feedback hack —
/// `.simultaneousGesture(DragGesture(minimumDistance: 0))` toggling a `pressed`
/// @State to drive a manual `scaleEffect`. Because the card lives inside the
/// sheet's single unified `ScrollView` (see `BottomSheetUnifiedScrollGuardTest`),
/// a *zero-distance* drag gesture claims the touch the instant the finger lands.
/// On release the host scroll view classifies the interaction as a drag, so the
/// `Button`'s tap recognizer never fires and the card is silently un-tappable —
/// the neighbouring `RouteCard` (a plain `Button`, no such gesture) stayed
/// tappable, which is exactly the asymmetry the user reported ("創建的路線的卡
/// 片這個還是沒辦法點擊"). Kin to [[project_dead_fab_sheet_wiring]].
///
/// The fix replaces the hand-rolled gesture with `PressableButtonStyle`, which
/// derives its press-scale from the system's own `ButtonStyle.isPressed` and
/// registers no competing gesture recognizer, so the tap reaches `onTap`.
///
/// SwiftUI view trees can't be introspected from XCTest, so — like the sibling
/// sheet/symbol guards — this scans the source for the two structural invariants
/// that together keep the card tappable inside a ScrollView.
final class CreateRouteEntryTappableGuardTest: XCTestCase {

    private func source() throws -> String {
        let url = Self.sourceRoot().appendingPathComponent("Views/Companion/CreateRouteView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Bounds the `CreateRouteEntryCard` struct body cheaply (declaration → next
    /// top-level `// MARK:`) without a full Swift parse, then strips comment
    /// lines so the explanatory prose mentioning the old gesture is not a false
    /// positive.
    private func entryCardCode() throws -> String {
        let src = try source()
        guard let structRange = src.range(of: "struct CreateRouteEntryCard: View {") else {
            XCTFail("Could not locate `struct CreateRouteEntryCard` to scan")
            return ""
        }
        let afterStruct = src[structRange.upperBound...]
        let rawBody: Substring
        if let nextMark = afterStruct.range(of: "\n// MARK:") {
            rawBody = afterStruct[..<nextMark.lowerBound]
        } else {
            rawBody = afterStruct
        }
        return rawBody
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
                return trimmed.hasPrefix("//") ? "" : line
            }
            .joined(separator: "\n")
    }

    /// Invariant 1: the card must NOT register a zero-distance drag gesture —
    /// that hack swallows the tap inside the sheet's ScrollView.
    func testNoTapSwallowingZeroDistanceDragGesture() throws {
        let code = try entryCardCode()
        XCTAssertFalse(
            code.contains("DragGesture(minimumDistance: 0)"),
            "CreateRouteEntryCard must NOT use `DragGesture(minimumDistance: 0)` "
                + "for press feedback — inside the BottomInfoSheet's ScrollView a "
                + "zero-distance drag claims the touch and the Button's tap never "
                + "fires, leaving the card un-tappable. Use PressableButtonStyle."
        )
        XCTAssertFalse(
            code.contains("simultaneousGesture"),
            "CreateRouteEntryCard must NOT attach a `simultaneousGesture` — it "
                + "competes with the host scroll view + Button tap and swallows the tap."
        )
    }

    /// Invariant 2: press feedback must come from `PressableButtonStyle`, which
    /// uses the system tap recognizer and keeps the card tappable.
    func testUsesPressableButtonStyle() throws {
        let code = try entryCardCode()
        XCTAssertTrue(
            code.contains("PressableButtonStyle"),
            "CreateRouteEntryCard should drive press feedback via "
                + "`PressableButtonStyle` so the tap is not stolen by a custom gesture."
        )
        XCTAssertTrue(
            code.contains("Button(action: onTap)") || code.contains("Button {"),
            "CreateRouteEntryCard must remain a real `Button` wired to `onTap`."
        )
    }

    // MARK: - Helpers

    /// `apps/ios/SoloCompass/` — derived from this test file's compile-time path
    /// (`…/SoloCompass/Tests/CreateRouteEntryTappableGuardTest.swift`).
    private static func sourceRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // SoloCompass/
    }
}

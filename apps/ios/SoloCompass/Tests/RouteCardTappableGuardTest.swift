import XCTest
@testable import SoloCompass

/// Structural regression guard for the *tappability* of `RouteCard` inside the
/// BottomInfoSheet's Routes section.
///
/// History: `RouteCard` drove its own press feedback with
/// `.simultaneousGesture(DragGesture(minimumDistance: 0))` toggling a `pressed`
/// @State for a manual `scaleEffect`. The card is rendered as the *label* of a
/// wrapping `Button { onSelectRoute(route) }` inside the sheet's single unified
/// `ScrollView`. A zero-distance drag claims the touch the instant a finger
/// lands: it played the press animation (so the card *looked* tappable — the
/// user saw "有按下效果") but on release the host scroll view classified the
/// interaction as a drag, so the wrapping Button's tap never fired and the route
/// detail never opened ("不跳转"). The neighbouring peek summary card (a plain
/// tap target, no such gesture) opened fine — exactly the asymmetry reported.
/// Kin to [[project_dead_fab_sheet_wiring]].
///
/// The fix removes the card's local gesture and moves press feedback to the
/// hosting Button via `PressableButtonStyle`, which derives its press-scale from
/// the system's own `ButtonStyle.isPressed` and registers no competing
/// recognizer, so the tap reaches the Button's action.
///
/// SwiftUI view trees can't be introspected from XCTest, so — like the sibling
/// sheet/symbol guards — this scans source for the structural invariants that
/// together keep the card tappable inside a ScrollView.
final class RouteCardTappableGuardTest: XCTestCase {

    private func source(_ relativePath: String) throws -> String {
        let url = Self.sourceRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Bounds the `RouteCard` struct body (declaration → next top-level
    /// `// MARK:`) and strips comment lines so the explanatory prose mentioning
    /// the old gesture is not a false positive.
    private func routeCardCode() throws -> String {
        let src = try source("Views/Companion/Components/RouteCard.swift")
        guard let structRange = src.range(of: "public struct RouteCard: View {") else {
            XCTFail("Could not locate `struct RouteCard` to scan")
            return ""
        }
        let afterStruct = src[structRange.upperBound...]
        let rawBody: Substring
        if let nextMark = afterStruct.range(of: "\n// MARK: - Preview") {
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

    /// Invariant 1: RouteCard must NOT register a tap-swallowing zero-distance
    /// drag gesture — inside the sheet's ScrollView it steals the wrapping
    /// Button's tap.
    func testRouteCardHasNoTapSwallowingGesture() throws {
        let code = try routeCardCode()
        XCTAssertFalse(
            code.contains("DragGesture(minimumDistance: 0)"),
            "RouteCard must NOT use `DragGesture(minimumDistance: 0)` for press "
                + "feedback — inside the BottomInfoSheet ScrollView it claims the "
                + "touch and the wrapping Button's tap never fires, so the route "
                + "detail won't open. Press feedback belongs on the host Button "
                + "(PressableButtonStyle)."
        )
        XCTAssertFalse(
            code.contains("simultaneousGesture"),
            "RouteCard must NOT attach a `simultaneousGesture` — it competes with "
                + "the host scroll view + Button tap and swallows the tap."
        )
    }

    /// Invariant 2: the Routes section's Button hosting RouteCard must use
    /// `PressableButtonStyle` (press feedback via the system tap recognizer), not
    /// `.plain` — so the tap opens the route detail AND the card still depresses.
    func testRoutesSectionButtonUsesPressableButtonStyle() throws {
        let sheet = try source("Views/Map/BottomInfoSheet.swift")
        guard let sectionRange = sheet.range(of: "struct RoutesSection: View {") else {
            XCTFail("Could not locate `struct RoutesSection` to scan")
            return
        }
        let afterSection = sheet[sectionRange.upperBound...]
        let body: Substring
        if let nextMark = afterSection.range(of: "\n// MARK:") {
            body = afterSection[..<nextMark.lowerBound]
        } else {
            body = afterSection
        }
        XCTAssertTrue(
            body.contains("PressableButtonStyle"),
            "RoutesSection's RouteCard Button should use PressableButtonStyle so "
                + "the tap reaches its action while still showing press feedback."
        )
        XCTAssertTrue(
            body.contains("onSelectRoute(route)"),
            "RoutesSection must keep a real Button wired to `onSelectRoute(route)`."
        )
    }

    // MARK: - Helpers

    /// `apps/ios/SoloCompass/` — derived from this test file's compile-time path
    /// (`…/SoloCompass/Tests/RouteCardTappableGuardTest.swift`).
    private static func sourceRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // SoloCompass/
    }
}

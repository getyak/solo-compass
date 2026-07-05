import XCTest
@testable import SoloCompass

/// Structural regression guard for the BottomInfoSheet's *single, unified*
/// scroll stream.
///
/// History: commit 1635c29 fixed a "two-viewport scroll conflict" — Routes +
/// Create-route were a non-scrollable header and only `NearbySection` carried
/// its own inner `ScrollView`, so a long Routes list pushed Nearby off-screen
/// and, at the `mid` detent, the route cards could not be scrolled at all (the
/// user's "拉一半…路线卡片滑不动"). The fix hosts the whole content closure in
/// ONE `ScrollView` and drops Nearby's nested one.
///
/// Commit f351c37 (peek summary card) then silently *reverted* both halves of
/// that fix, re-breaking the scroll. SwiftUI view trees can't be introspected
/// from XCTest, and `ImageRenderer` doesn't expand `ScrollView`/`LazyVStack`,
/// so behavioural assertion isn't available here. Instead this test scans the
/// source the same way `SFSymbolExistenceTests` does and asserts the two
/// structural invariants that together guarantee one continuous scroll stream:
///
///   1. The host `body` wraps the `content(currentDetent, $sortMode)` closure
///      in a `ScrollView` (the unified scroll layer exists).
///   2. `NearbySection`'s body contains NO `ScrollView` (no nested scroll
///      island that would re-create the two-viewport conflict).
///
/// If a future refactor reverts either invariant, this fails loudly instead of
/// shipping a sheet whose route cards silently won't scroll.
final class BottomSheetUnifiedScrollGuardTest: XCTestCase {

    private func sheetSource() throws -> String {
        let url = Self.sourceRoot().appendingPathComponent("Views/Map/BottomInfoSheet.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// `NearbySection` lives in its own file — the invariant-2 scan was
    /// silently failing after the struct moved out of BottomInfoSheet.swift.
    private func nearbySource() throws -> String {
        let url = Self.sourceRoot().appendingPathComponent("Views/Map/NearbySectionView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Invariant 1: the content closure is hosted inside a `ScrollView` in the
    /// sheet body, so Routes → Create-route → Nearby form one scroll stream.
    func testContentClosureIsWrappedInScrollView() throws {
        let source = try sheetSource()

        // The body must contain a `ScrollView {` whose body invokes the content
        // closure. We assert both tokens exist and that a `ScrollView` opens
        // before the `content(contentDetent` call (the closure lives inside it).
        // `contentDetent` is the drag-aware effective detent (pre-builds the
        // list on drag start); the invariant is unchanged.
        guard let scrollRange = source.range(of: "ScrollView {"),
              let contentRange = source.range(of: "content(contentDetent") else {
            XCTFail("Expected a `ScrollView {` hosting `content(contentDetent…)` in the sheet body")
            return
        }
        XCTAssertLessThan(
            scrollRange.lowerBound, contentRange.lowerBound,
            "The content closure must be nested INSIDE the unified ScrollView "
                + "(ScrollView must open before `content(contentDetent…)`). A bare "
                + "`content + Spacer` makes the Routes/Create rows un-scrollable at mid."
        )
    }

    /// Invariant 3: the sheet must be positioned with fixed-height + `.offset`
    /// translation, NOT a per-frame `.frame(height: displayHeight)` resize.
    /// The resize shape forced a full layout of the header rows, the
    /// ScrollView viewport, and the material background on every drag/settle
    /// frame — the expansion jank this refactor removed. If a future change
    /// reverts to sizing the sheet by its display height, this fails loudly.
    func testSheetUsesOffsetTranslationNotFrameResize() throws {
        let source = try sheetSource()
        XCTAssertTrue(
            source.contains(".offset(y: maxHeight - displayHeight)"),
            "The sheet must slide via .offset — a translation is a render-phase "
                + "transform; resizing re-layouts the whole subtree every frame."
        )
        XCTAssertFalse(
            source.contains(".frame(height: displayHeight)"),
            "Per-frame .frame(height: displayHeight) resize re-introduces the "
                + "expansion jank (full layout + material re-render every frame)."
        )
    }

    /// Invariant 2: `NearbySection` must NOT host its own `ScrollView` — a
    /// nested scroll island re-creates the two-viewport conflict that hid the
    /// list and froze the route cards at `mid`.
    func testNearbySectionHasNoNestedScrollView() throws {
        let source = try nearbySource()

        guard let structRange = source.range(of: "struct NearbySection: View {") else {
            XCTFail("Could not locate `struct NearbySection` to scan")
            return
        }
        // Scan from the struct declaration to the next top-level `// MARK:` (the
        // section that follows NearbySection), which bounds its body cheaply
        // without a full Swift parse.
        let afterStruct = source[structRange.upperBound...]
        let rawBody: Substring
        if let nextMark = afterStruct.range(of: "\n// MARK:") {
            rawBody = afterStruct[..<nextMark.lowerBound]
        } else {
            rawBody = afterStruct
        }

        // Strip comment lines before scanning: the explanatory comments
        // intentionally mention `ScrollView` ("no nested ScrollView here…"),
        // and matching those would be a false positive. We only care whether
        // *code* re-introduces a nested ScrollView.
        let codeOnly = rawBody
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
                return trimmed.hasPrefix("//") ? "" : line
            }
            .joined(separator: "\n")

        XCTAssertFalse(
            codeOnly.contains("ScrollView"),
            "NearbySection must NOT contain a nested `ScrollView` in CODE — the "
                + "host BottomInfoSheet already wraps the whole content closure in "
                + "one ScrollView. A nested one re-introduces the two-viewport "
                + "conflict (regression of 1635c29 by f351c37)."
        )
    }

    // MARK: - Helpers

    /// `apps/ios/SoloCompass/` — derived from this test file's compile-time path
    /// (`…/SoloCompass/Tests/BottomSheetUnifiedScrollGuardTest.swift`).
    private static func sourceRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // SoloCompass/
    }
}

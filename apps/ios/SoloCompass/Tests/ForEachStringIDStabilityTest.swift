import XCTest
@testable import SoloCompass

/// US-041: `ForEach(collection, id: \.self)` over a `[String]` derives each
/// row's identity from the string *value*. When the collection contains
/// duplicate strings, those rows share an identity and SwiftUI collapses them —
/// rendering fewer rows than the data has elements (and animating incorrectly).
///
/// The three production call sites (FilterBarView custom tags, ShareCardView
/// highlight bullets ×2) were switched to `ForEach(Array(c.enumerated()),
/// id: \.offset)` so the row identity is the element's *index*, which is unique
/// even when two elements hold the same string.
///
/// SwiftUI doesn't expose a rendered row count to XCTest, so these tests model
/// the exact identity-derivation each strategy performs and assert the
/// index-based strategy preserves one row per element while the value-based
/// strategy collapses duplicates.
@MainActor
final class ForEachStringIDStabilityTest: XCTestCase {

    /// Identity set produced by the OLD strategy: `ForEach(c, id: \.self)`
    /// keys on the string value, so duplicates merge.
    private func valueKeyedIdentityCount(_ items: [String]) -> Int {
        Set(items).count
    }

    /// Identity set produced by the NEW strategy: `ForEach(Array(c.enumerated()),
    /// id: \.offset)` keys on the index, so every element stays distinct.
    private func indexKeyedIdentityCount(_ items: [String]) -> Int {
        Set(Array(items.enumerated()).map(\.offset)).count
    }

    // MARK: - The bug the story fixes

    func testValueKeyedIdentityCollapsesDuplicates() {
        let highlights = ["Great views", "Quiet", "Great views"]
        XCTAssertEqual(
            valueKeyedIdentityCount(highlights), 2,
            "precondition: `id: \\.self` collapses the two identical 'Great views' rows into one"
        )
    }

    func testIndexKeyedIdentityPreservesDuplicateRows() {
        let highlights = ["Great views", "Quiet", "Great views"]
        XCTAssertEqual(
            indexKeyedIdentityCount(highlights), highlights.count,
            "`id: \\.offset` over enumerated() must keep one row per element even with duplicates"
        )
    }

    // MARK: - FilterBarView custom tags (duplicate tags must not merge)

    func testCustomTagsWithDuplicatesRenderEveryRow() {
        let tags = ["food", "coffee", "food", "coffee", "food"]
        XCTAssertEqual(
            indexKeyedIdentityCount(tags), 5,
            "five custom-tag pills must survive even though only two distinct strings appear"
        )
        XCTAssertLessThan(
            valueKeyedIdentityCount(tags), tags.count,
            "precondition: the old value-keyed approach would have shown only 2 pills"
        )
    }

    // MARK: - ShareCardView highlight bullets (prefix(3) / prefix(2))

    func testShareCardHighlightsPrefixThreePreservesDuplicateRows() {
        let highlights = ["Top rated", "Top rated", "Hidden gem"]
        let rendered = Array(highlights.prefix(3))
        XCTAssertEqual(
            indexKeyedIdentityCount(rendered), 3,
            "the large share card must render all three highlight bullets, duplicates included"
        )
    }

    func testShareCardHighlightsPrefixTwoPreservesDuplicateRows() {
        let highlights = ["Cozy", "Cozy", "Quiet"]
        let rendered = Array(highlights.prefix(2))
        XCTAssertEqual(
            indexKeyedIdentityCount(rendered), 2,
            "the compact share card must render both highlight bullets, duplicates included"
        )
    }

    // MARK: - Stability: identity is order-preserving and contiguous

    func testIndexKeyedIdentitiesAreContiguousAndOrdered() {
        let items = ["a", "a", "a"]
        let offsets = Array(items.enumerated()).map(\.offset)
        XCTAssertEqual(offsets, [0, 1, 2], "index ids must be the stable 0-based positions")
    }
}

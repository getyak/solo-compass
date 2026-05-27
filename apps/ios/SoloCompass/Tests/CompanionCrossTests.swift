import XCTest
@testable import SoloCompass

// MARK: - US-019: reporterWeight sort order and threshold

final class ReporterWeightSortTests: XCTestCase {

    // MARK: Helpers

    private func makePost(id: String, reporterWeight: Double) -> DiscoverPost {
        DiscoverPost(
            id: id,
            handle: "🧭",
            blurb: "test",
            categories: [],
            cityCode: "TYO",
            mode: "itinerary",
            activeFrom: nil,
            activeTo: nil,
            reporterWeight: reporterWeight
        )
    }

    // MARK: Sort order

    func testSortsByReporterWeightDescending() {
        let posts = [
            makePost(id: "a", reporterWeight: 0.4),
            makePost(id: "b", reporterWeight: 1.0),
            makePost(id: "c", reporterWeight: 0.6),
        ]
        let sorted = posts.sortedByReporterWeight()
        XCTAssertEqual(sorted.map(\.id), ["b", "c", "a"],
            "Posts must be ordered highest reporter_weight first")
    }

    func testEqualWeightsPreserveRelativeOrder() {
        let posts = [
            makePost(id: "x", reporterWeight: 0.8),
            makePost(id: "y", reporterWeight: 0.8),
        ]
        let sorted = posts.sortedByReporterWeight()
        XCTAssertEqual(sorted.map(\.id), ["x", "y"],
            "Equal-weight posts must keep their existing order")
    }

    // MARK: Threshold

    func testBelowThresholdPostIsExcluded() {
        let posts = [
            makePost(id: "low", reporterWeight: 0.2),   // below 0.3 — excluded
            makePost(id: "ok", reporterWeight: 0.5),
        ]
        let visible = posts.aboveReporterWeightThreshold()
        XCTAssertEqual(visible.map(\.id), ["ok"],
            "Posts from authors with reporter_weight < 0.3 must be excluded")
    }

    func testExactThresholdIsIncluded() {
        let posts = [makePost(id: "edge", reporterWeight: 0.3)]
        let visible = posts.aboveReporterWeightThreshold()
        XCTAssertEqual(visible.count, 1,
            "reporter_weight == threshold (0.3) must still be included")
    }

    func testZeroWeightIsExcluded() {
        let posts = [makePost(id: "zero", reporterWeight: 0.0)]
        XCTAssertTrue(posts.aboveReporterWeightThreshold().isEmpty,
            "reporter_weight == 0 must be excluded")
    }

    func testFullWeightAlwaysIncluded() {
        let posts = [makePost(id: "full", reporterWeight: 1.0)]
        XCTAssertEqual(posts.aboveReporterWeightThreshold().count, 1)
    }

    // MARK: Combined filter + sort

    func testFilterThenSortChain() {
        let posts = [
            makePost(id: "excluded", reporterWeight: 0.1),
            makePost(id: "low",      reporterWeight: 0.5),
            makePost(id: "high",     reporterWeight: 0.9),
        ]
        let result = posts.aboveReporterWeightThreshold().sortedByReporterWeight()
        XCTAssertEqual(result.map(\.id), ["high", "low"],
            "Combined filter + sort: excluded, then high-weight first")
    }
}

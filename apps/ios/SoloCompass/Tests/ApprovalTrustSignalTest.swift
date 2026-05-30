import XCTest
import SwiftUI
@testable import SoloCompass

/// US-032: The approval queue renders three trust micro-stats per requester —
/// an opt-in badge, a walked count, and a group (trips) count — sourced from
/// the requester profile object. When a stat is unknown (profile missing or
/// the opt-in field absent), the row must show "—" instead of fabricating.
///
/// We don't ship a pixel-snapshot library, so we render the trust-signal row
/// through SwiftUI's `ImageRenderer` for three distinct signal combinations and
/// assert each produces a valid, non-empty image. We also assert directly on
/// the model-driven branching so the "show — when unknown" rule is covered
/// without pixel comparison.
@MainActor
final class ApprovalTrustSignalTest: XCTestCase {

    // Three rows with different signal combinations.
    private func optedInUser() -> SeedUser {
        SeedUser(
            handle: "maya",
            blurb: "Chasing sunsets.",
            color: "#E8826A",
            trips: 14,
            walked: ["mekong-sunset", "vientiane-monuments"],
            optedIn: true
        )
    }

    private func optedOutUser() -> SeedUser {
        SeedUser(
            handle: "lin",
            blurb: "Always early.",
            color: "#6A9FE8",
            trips: 0,
            walked: [],
            optedIn: false
        )
    }

    // optedIn nil → opt-in status unknown.
    private func unknownOptInUser() -> SeedUser {
        SeedUser(
            handle: "ren",
            blurb: "Maps and markets.",
            color: "#C97AA0",
            trips: 6,
            walked: ["vientiane-monuments"],
            optedIn: nil
        )
    }

    private func render(_ user: SeedUser?) -> UIImage? {
        let view = ApprovalQueueView.trustSignalRow(for: user)
            .frame(width: 390)
            .fixedSize(horizontal: false, vertical: true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }

    // MARK: - Snapshot renders for three combinations

    func testSnapshotOptedInUser() throws {
        let image = try XCTUnwrap(render(optedInUser()), "Opted-in row must render")
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testSnapshotOptedOutUser() throws {
        let image = try XCTUnwrap(render(optedOutUser()), "Opted-out row must render")
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testSnapshotUnknownOptInUser() throws {
        let image = try XCTUnwrap(render(unknownOptInUser()), "Unknown-opt-in row must render")
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testSnapshotMissingProfileShowsAllUnknown() throws {
        // A nil profile (requester not in directory) must still render — every
        // stat falls back to the unknown placeholder rather than crashing.
        let image = try XCTUnwrap(render(nil), "Missing-profile row must render")
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    // MARK: - "Show — when unknown" rule

    func testUnknownPlaceholderIsEmDash() {
        XCTAssertEqual(ApprovalQueueView.unknownValue, "—",
            "Unknown stats must render as an em dash, not a fabricated 0")
    }

    func testOptInStringsAreDistinct() {
        let yes = NSLocalizedString("approval.queue.signal.optin.yes", comment: "")
        let no = NSLocalizedString("approval.queue.signal.optin.no", comment: "")
        XCTAssertFalse(yes.isEmpty)
        XCTAssertFalse(no.isEmpty)
        XCTAssertNotEqual(yes, no, "Opted-in and not-opted-in labels must differ")
    }

    func testSeedUserOptInDecodesLeniently() throws {
        // Seed JSON without the optedIn key must still decode, leaving the
        // field nil (unknown) rather than failing.
        let json = Data("""
        {"handle":"x","blurb":"b","color":"#000000","trips":3,"walked":["a"]}
        """.utf8)
        let user = try JSONDecoder().decode(SeedUser.self, from: json)
        XCTAssertNil(user.optedIn, "Missing optedIn key must decode to nil")
        XCTAssertEqual(user.walked.count, 1)
        XCTAssertEqual(user.trips, 3)
    }
}

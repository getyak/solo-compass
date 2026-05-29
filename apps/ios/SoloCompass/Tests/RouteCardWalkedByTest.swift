import XCTest
import SwiftUI
@testable import SoloCompass

/// CompareCanvas A-003 coverage: when the companion layer is off (or the route
/// has no companion slot), `RouteCard` surfaces a walked-by social-proof row —
/// an `AvatarStack(maxVisible: 4)` + "<count> 位旅人走过" + chevron — so the
/// reader can gauge how many travelers have walked the route.
///
/// We don't ship a snapshot library, so we render the card through SwiftUI's
/// `ImageRenderer` at three walker counts (0, 3, and 12 — the +N more case) and
/// assert each produces a valid, non-empty image. We also assert the
/// model-level invariants: the row shows when the companion layer is off, the
/// avatar stack caps at 4 visible, and the label reflects `walkedByCount`.
@MainActor
final class RouteCardWalkedByTest: XCTestCase {

    private func makeRoute(
        walkers: Int,
        ids: [String],
        companion: RouteCompanion? = nil
    ) -> Route {
        Route(
            id: RouteId(rawValue: "r-w\(walkers)"),
            title: "Riverside Loop",
            summary: "A walk \(walkers) travelers have taken.",
            experienceIds: ["e0", "e1"],
            cityCode: "VTE",
            region: "Riverfront",
            estimatedDuration: 75,
            distanceMeters: 1500,
            pace: .relaxed,
            tags: ["nature"],
            source: .editorial,
            verification: RouteVerification(status: .walkedBy, walkedByCount: walkers, walkedBy: ids),
            companion: companion
        )
    }

    private func render(_ card: RouteCard) -> UIImage? {
        let view = card
            .frame(width: 390) // iPhone 17 Pro logical width
            .fixedSize(horizontal: false, vertical: true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }

    // MARK: - Snapshot renders at 0 / 3 / 12 walkers (the +N more case)

    func testSnapshotZeroWalkers() throws {
        let image = try XCTUnwrap(render(RouteCard(route: makeRoute(walkers: 0, ids: []))))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testSnapshotThreeWalkers() throws {
        let route = makeRoute(walkers: 3, ids: ["maya", "leon", "rina"])
        let image = try XCTUnwrap(render(RouteCard(route: route)))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testSnapshotTwelveWalkers() throws {
        let route = makeRoute(walkers: 12, ids: ["a", "b", "c", "d", "e", "f"])
        let image = try XCTUnwrap(render(RouteCard(route: route)))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    // MARK: - Model-level invariants

    func testWalkedByShownWhenCompanionOff() {
        let card = RouteCard(route: makeRoute(walkers: 3, ids: ["maya", "leon", "rina"]))
        XCTAssertTrue(card.showWalkedBy, "Walked-by row shows when the companion layer is off")
    }

    func testWalkedByShownWhenNoCompanionEvenIfCompanionOn() {
        let card = RouteCard(route: makeRoute(walkers: 3, ids: []), companionOn: true)
        XCTAssertTrue(card.showWalkedBy, "Walked-by row shows when the route has no companion slot")
    }

    func testWalkedByHiddenWhenCompanionOnAndPresent() {
        let companion = RouteCompanion(
            status: .open,
            hostId: "maya",
            departureWindow: DepartureWindow(startDate: "2026-06-10", to: "2026-06-12", time: "morning"),
            departureLabel: "Jun 10–12 · morning",
            maxMembers: 4,
            confirmedMembers: ["maya"]
        )
        let card = RouteCard(route: makeRoute(walkers: 3, ids: [], companion: companion), companionOn: true)
        XCTAssertFalse(card.showWalkedBy, "Walked-by row hides when companion is on and present")
    }

    func testZeroWalkersHasEmptyAvatarIds() {
        let card = RouteCard(route: makeRoute(walkers: 0, ids: []))
        XCTAssertTrue(card.walkedByIds.isEmpty, "Zero walkers yields no avatars")
        XCTAssertTrue(card.walkedByLabel.contains("0"), "Label reflects a zero count")
    }

    func testTwelveWalkersOverflowsBeyondFour() {
        // 12 walkers with only 6 ids supplied: AvatarStack(maxVisible: 4) shows
        // 4 + a "+N" overflow bubble. We assert the backing ids exceed the cap.
        let card = RouteCard(route: makeRoute(walkers: 12, ids: ["a", "b", "c", "d", "e", "f"]))
        XCTAssertGreaterThan(card.walkedByIds.count, 4, "12-walker case overflows the 4-visible cap")
        XCTAssertTrue(card.walkedByLabel.contains("12"), "Label reflects the 12 count")
    }

    func testWalkedByIdsSynthesizedWhenEmptyButCountPositive() {
        let card = RouteCard(route: makeRoute(walkers: 12, ids: []))
        XCTAssertEqual(card.walkedByIds.count, 12, "Empty ids with positive count synthesize placeholders")
    }
}

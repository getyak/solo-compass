import XCTest
import SwiftUI
@testable import SoloCompass

/// CompareCanvas A-002 coverage: when a route has a companion slot, `RouteCard`
/// renders an inline recruit-mini strip below the title — host / N filled out of
/// M / departure — so the recruiting state reads without opening detail.
///
/// We don't ship a snapshot library, so we render the card through SwiftUI's
/// `ImageRenderer` across all four `CompanionStatus` variants and assert each
/// produces a valid, non-empty image. We also assert the model-level invariants:
/// a route without a companion exposes no mini, and each status maps to the
/// expected text content and tone color.
@MainActor
final class RouteCardRecruitMiniTest: XCTestCase {

    private func makeRoute(
        status: CompanionStatus?,
        confirmedMembers: [String] = ["maya", "leon"]
    ) -> Route {
        let companion: RouteCompanion? = status.map { status in
            RouteCompanion(
                status: status,
                hostId: "maya",
                departureWindow: DepartureWindow(startDate: "2026-06-10", to: "2026-06-12", time: "morning"),
                departureLabel: "Jun 10–12 · morning",
                maxMembers: 4,
                confirmedMembers: confirmedMembers
            )
        }
        return Route(
            id: RouteId(rawValue: "r-\(status?.rawValue ?? "none")"),
            title: "Riverside Loop",
            summary: "A walk with companions.",
            experienceIds: ["e0", "e1"],
            cityCode: "VTE",
            region: "Riverfront",
            estimatedDuration: 75,
            distanceMeters: 1500,
            pace: .relaxed,
            tags: ["nature"],
            source: .editorial,
            verification: RouteVerification(status: .verified, walkedByCount: 4, walkedBy: []),
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

    // MARK: - Snapshot renders for all four status variants

    func testSnapshotOpen() throws {
        let image = try XCTUnwrap(render(RouteCard(route: makeRoute(status: .open))))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testSnapshotForming() throws {
        let image = try XCTUnwrap(render(RouteCard(route: makeRoute(status: .forming))))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testSnapshotClosed() throws {
        let image = try XCTUnwrap(render(RouteCard(route: makeRoute(status: .closed))))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testSnapshotCompleted() throws {
        let image = try XCTUnwrap(render(RouteCard(route: makeRoute(status: .completed))))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    // MARK: - Model-level invariants

    func testNoCompanionHasNoMini() {
        let card = RouteCard(route: makeRoute(status: nil))
        XCTAssertNil(card.recruitMini, "A route without a companion renders no recruit-mini strip")
    }

    func testOpenMiniShowsHostSlotsDeparture() {
        let card = RouteCard(route: makeRoute(status: .open))
        let mini = try? XCTUnwrap(card.recruitMini)
        XCTAssertTrue(mini?.text.contains("maya") ?? false, "Open mini names the host")
        XCTAssertTrue(mini?.text.contains("2/4") ?? false, "Open mini shows N/M filled")
        XCTAssertTrue(mini?.text.contains("Jun 10–12 · morning") ?? false, "Open mini shows departure")
        XCTAssertEqual(mini?.tone, CT.accent, "Open uses the accent tone")
    }

    func testFormingMiniUsesAmberTone() {
        let card = RouteCard(route: makeRoute(status: .forming))
        XCTAssertEqual(card.recruitMini?.tone, CT.toneForming, "Forming uses the amber tone")
        XCTAssertTrue(card.recruitMini?.text.contains("2/4") ?? false, "Forming mini shows N/M filled")
    }

    func testClosedMiniShowsMemberCount() {
        let card = RouteCard(route: makeRoute(status: .closed, confirmedMembers: ["maya", "leon", "rina"]))
        let mini = card.recruitMini
        XCTAssertTrue(mini?.text.contains("3") ?? false, "Closed mini shows confirmed member count")
        XCTAssertEqual(mini?.tone, CT.toneClosed, "Closed uses the closed tone")
    }

    func testCompletedMiniUsesGreenTone() {
        let card = RouteCard(route: makeRoute(status: .completed))
        XCTAssertEqual(card.recruitMini?.tone, CT.toneCompleted, "Completed uses the green tone")
    }
}

import XCTest
import SwiftUI
@testable import SoloCompass

/// Coverage for the 此刻理由 (now-reason) banner on `RouteCard`.
///
/// The banner only surfaces when the card is in now-context AND the route carries
/// a non-empty `reasonNow`. We assert the model-level `showsNowReason` invariant
/// across the four combinations, then render the banner state to confirm it
/// produces a valid image (no snapshot library is shipped).
@MainActor
final class RouteCardNowReasonTests: XCTestCase {

    private func makeRoute(reasonNow: String?) -> Route {
        Route(
            id: RouteId(rawValue: "r-now"),
            title: "Mekong Sunset Walk",
            summary: "Promenade along the river.",
            experienceIds: ["e1", "e2", "e3"],
            cityCode: "VTE",
            region: "Riverfront",
            estimatedDuration: 90,
            distanceMeters: 1200,
            pace: .relaxed,
            tags: ["nature"],
            source: .editorial,
            bestStartHour: 17.0,
            bestNow: true,
            reasonNow: reasonNow,
            verification: RouteVerification(status: .verified, walkedByCount: 12, walkedBy: [])
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

    // MARK: - showsNowReason invariant

    func testBannerShownInNowContextWithReason() {
        let card = RouteCard(route: makeRoute(reasonNow: "日落將至 · 30 分鐘後是最佳光線"), nowContext: true)
        XCTAssertTrue(card.showsNowReason)
    }

    func testBannerHiddenWithoutNowContext() {
        let card = RouteCard(route: makeRoute(reasonNow: "日落將至 · 30 分鐘後是最佳光線"), nowContext: false)
        XCTAssertFalse(card.showsNowReason)
    }

    func testBannerHiddenWhenReasonNil() {
        let card = RouteCard(route: makeRoute(reasonNow: nil), nowContext: true)
        XCTAssertFalse(card.showsNowReason)
    }

    func testBannerHiddenWhenReasonEmpty() {
        let card = RouteCard(route: makeRoute(reasonNow: ""), nowContext: true)
        XCTAssertFalse(card.showsNowReason)
    }

    // MARK: - Render

    func testRendersWithBanner() throws {
        let card = RouteCard(route: makeRoute(reasonNow: "日落將至 · 30 分鐘後是最佳光線"), nowContext: true)
        let image = try XCTUnwrap(render(card))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }
}

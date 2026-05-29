import XCTest
import SwiftUI
@testable import SoloCompass

/// CompareCanvas A-001 coverage: each `RouteCard` renders a stop-strip
/// breadcrumb — one colored disc per stop, joined by 1px connectors — so the
/// journey is previewable at a glance.
///
/// We don't ship a snapshot library, so we render the card through SwiftUI's
/// `ImageRenderer` at three stop counts (2, 3, 5) and assert each produces a
/// valid, non-empty image. We also assert the model-level invariant that the
/// strip exposes exactly one color per stop, all sourced from `CategoryVisual`.
@MainActor
final class RouteCardStopStripTest: XCTestCase {

    private func makeRoute(stops: Int) -> Route {
        Route(
            id: RouteId(rawValue: "r-\(stops)"),
            title: "Riverside Loop",
            summary: "A walk with \(stops) stops.",
            experienceIds: (0..<stops).map { "e\($0)" },
            cityCode: "VTE",
            region: "Riverfront",
            estimatedDuration: 75,
            distanceMeters: 1500,
            pace: .relaxed,
            tags: ["nature"],
            source: .editorial,
            verification: RouteVerification(status: .verified, walkedByCount: 4, walkedBy: [])
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

    // MARK: - Snapshot renders at 2 / 3 / 5 stops

    func testSnapshotTwoStops() throws {
        let image = try XCTUnwrap(render(RouteCard(route: makeRoute(stops: 2))))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testSnapshotThreeStops() throws {
        let image = try XCTUnwrap(render(RouteCard(route: makeRoute(stops: 3))))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testSnapshotFiveStops() throws {
        let image = try XCTUnwrap(render(RouteCard(route: makeRoute(stops: 5))))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    // MARK: - One disc per stop, colors from CategoryVisual

    func testStripExposesOneColorPerStop() {
        for count in [2, 3, 5] {
            let card = RouteCard(route: makeRoute(stops: count))
            XCTAssertEqual(
                card.stopColors.count, count,
                "Stop-strip must render exactly one disc per stop (count=\(count))"
            )
        }
    }

    func testStripColorsAreCategoryVisualColors() {
        let card = RouteCard(route: makeRoute(stops: 5))
        // Every disc color must be one of the eight CategoryVisual primary colors.
        let palette: Set<String> = Set(
            ExperienceCategory.allCases.map { Self.describe(CategoryVisual.colorPair(for: $0).0) }
        )
        for color in card.stopColors {
            XCTAssertTrue(
                palette.contains(Self.describe(color)),
                "Every stop disc color must come from CategoryVisual"
            )
        }
    }

    func testEmptyRouteHasNoStrip() {
        let card = RouteCard(route: makeRoute(stops: 0))
        XCTAssertTrue(card.stopColors.isEmpty, "A route with no stops renders no strip")
    }

    /// Stable string identity for a SwiftUI `Color` via its resolved sRGB
    /// components, so two colors built from the same RGB compare equal.
    private static func describe(_ color: Color) -> String {
        let resolved = color.resolve(in: EnvironmentValues())
        return String(format: "%.3f,%.3f,%.3f", resolved.red, resolved.green, resolved.blue)
    }
}

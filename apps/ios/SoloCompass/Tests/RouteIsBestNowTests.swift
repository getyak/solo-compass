import XCTest
@testable import SoloCompass

/// Coverage for `Route.isBestNow(at:)` — the runtime now-window check that powers
/// the 此刻適合 routes section. Because the static seed `bestNow` flag is all-false
/// today, the section relies on this method deriving the window from `bestStartHour`.
final class RouteIsBestNowTests: XCTestCase {

    /// Build a Date at a fixed local hour today (minute 0) for deterministic checks.
    private func date(hour: Int) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = 0
        return cal.date(from: comps)!
    }

    private func makeRoute(bestStartHour: Double?, bestNow: Bool = false) -> Route {
        Route(
            id: RouteId(rawValue: "r-now"),
            title: "Mekong Sunset",
            summary: "Riverside walk.",
            experienceIds: ["e1"],
            cityCode: "VTE",
            region: "Riverfront",
            estimatedDuration: 90,
            distanceMeters: 1200,
            pace: .relaxed,
            tags: ["nature"],
            source: .editorial,
            bestStartHour: bestStartHour,
            bestNow: bestNow
        )
    }

    // MARK: - bestStartHour drives the window

    func testInsideWindowAtStartHour() {
        let route = makeRoute(bestStartHour: 17.0)
        XCTAssertTrue(route.isBestNow(at: date(hour: 17)))
    }

    func testInsideWindowMidway() {
        let route = makeRoute(bestStartHour: 17.0)
        // Window is [17, 20); hour 19 is still inside.
        XCTAssertTrue(route.isBestNow(at: date(hour: 19)))
    }

    func testOutsideWindowBeforeStart() {
        let route = makeRoute(bestStartHour: 17.0)
        XCTAssertFalse(route.isBestNow(at: date(hour: 16)))
    }

    func testOutsideWindowAtEndBoundary() {
        let route = makeRoute(bestStartHour: 17.0)
        // End boundary is exclusive: 17 + 3 = 20 is no longer best-now.
        XCTAssertFalse(route.isBestNow(at: date(hour: 20)))
    }

    func testWindowWrapsPastMidnight() {
        let route = makeRoute(bestStartHour: 23.0)
        // [23, 26) ⇒ 23, 0, 1 are inside; 2 is outside.
        XCTAssertTrue(route.isBestNow(at: date(hour: 23)))
        XCTAssertTrue(route.isBestNow(at: date(hour: 0)))
        XCTAssertTrue(route.isBestNow(at: date(hour: 1)))
        XCTAssertFalse(route.isBestNow(at: date(hour: 2)))
    }

    // MARK: - Fallback to static bestNow when no bestStartHour

    func testFallsBackToStaticBestNowTrue() {
        let route = makeRoute(bestStartHour: nil, bestNow: true)
        XCTAssertTrue(route.isBestNow(at: date(hour: 3)))
    }

    func testFallsBackToStaticBestNowFalse() {
        let route = makeRoute(bestStartHour: nil, bestNow: false)
        XCTAssertFalse(route.isBestNow(at: date(hour: 3)))
    }
}

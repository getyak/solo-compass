import XCTest
@testable import SoloCompass

/// Coverage for `Experience.minutesUntilNextBestWindow(at:within:)`, which powers
/// the "· opens in Nm" tail on the best-time hint pill in ExperienceCardView.
///
/// A static "Best 7–9am" pill reads the same whether the window opens in 20
/// minutes or in 8 hours; this method lets the card highlight only the imminent
/// case, so these tests pin its boundaries: imminent window, far window, already
/// best now, no upcoming window today, and the `within` budget.
final class BestTimeOpensInTests: XCTestCase {

    /// A Date at a fixed local hour + minute today, for deterministic checks.
    private func date(hour: Int, minute: Int = 0) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return cal.date(from: comps)!
    }

    private static func makeExp(windows: [TimeWindow]) -> Experience {
        let now = Date()
        return Experience(
            id: "opens_in_fixture",
            title: "Opens In Fixture",
            oneLiner: "Test",
            whyItMatters: "Test",
            category: .coffee,
            location: ExperienceLocation(coordinates: [100.0, 13.0], cityCode: "bkk"),
            bestTimes: windows,
            durationMinutes: .init(min: 30, max: 60),
            howTo: [],
            realInconveniences: [],
            soloScore: SoloScore(
                overall: 7.0,
                breakdown: .init(
                    seatingFriendly: 7, soloPatronRatio: 7, staffPressure: 7,
                    soloPortioning: 7, ambianceFit: 7, safety: 7
                ),
                basedOnCount: 1
            ),
            sources: [InformationSource(type: .user, attribution: "fixture", verifiedAt: now)],
            confidence: Confidence(
                level: 3,
                lastVerifiedAt: now,
                reason: "Fixture",
                signals: .init(aiScrapeAgeDays: 1, passiveGpsHits30d: 0,
                               activeReports30d: 0, trustedVerifications: 0)
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .active,
            createdAt: now,
            updatedAt: now
        )
    }

    /// Window opens at 10:00; from 09:30 that's 30 minutes out — within the
    /// default 90-minute budget, so the nudge fires.
    func testImminentWindowReportsMinutes() {
        let exp = Self.makeExp(windows: [TimeWindow(startHour: 10, endHour: 12)])
        let mins = exp.minutesUntilNextBestWindow(at: date(hour: 9, minute: 30))
        XCTAssertEqual(mins, 30)
    }

    /// Window opens at 10:00 but it's only 06:00 — 4 hours out, beyond the
    /// 90-minute budget, so no nudge.
    func testFarWindowReturnsNil() {
        let exp = Self.makeExp(windows: [TimeWindow(startHour: 10, endHour: 12)])
        XCTAssertNil(exp.minutesUntilNextBestWindow(at: date(hour: 6)))
    }

    /// Exactly at the 90-minute budget boundary the nudge still fires; one
    /// minute past it does not.
    func testWithinBudgetBoundary() {
        let exp = Self.makeExp(windows: [TimeWindow(startHour: 10, endHour: 12)])
        XCTAssertEqual(exp.minutesUntilNextBestWindow(at: date(hour: 8, minute: 30)), 90)
        XCTAssertNil(exp.minutesUntilNextBestWindow(at: date(hour: 8, minute: 29)))
    }

    /// While the window is open the experience is best-now, so the "opens in"
    /// nudge is suppressed (the BestNowBadge takes over instead).
    func testBestNowReturnsNil() {
        let exp = Self.makeExp(windows: [TimeWindow(startHour: 10, endHour: 12)])
        XCTAssertTrue(exp.isBestNow(at: date(hour: 11)))
        XCTAssertNil(exp.minutesUntilNextBestWindow(at: date(hour: 11)))
    }

    /// After the only window has closed for the day there is nothing upcoming,
    /// so the method returns nil rather than wrapping to tomorrow.
    func testNoUpcomingWindowTodayReturnsNil() {
        let exp = Self.makeExp(windows: [TimeWindow(startHour: 10, endHour: 12)])
        XCTAssertNil(exp.minutesUntilNextBestWindow(at: date(hour: 15)))
    }

    /// With no best times at all there is no window to open.
    func testEmptyBestTimesReturnsNil() {
        let exp = Self.makeExp(windows: [])
        XCTAssertNil(exp.minutesUntilNextBestWindow(at: date(hour: 9)))
    }

    /// Of two upcoming windows the soonest one wins. From 09:00, the 10:00
    /// window (60 min) is chosen over the 14:00 window.
    func testPicksSoonestUpcomingWindow() {
        let exp = Self.makeExp(windows: [
            TimeWindow(startHour: 14, endHour: 16),
            TimeWindow(startHour: 10, endHour: 12),
        ])
        XCTAssertEqual(exp.minutesUntilNextBestWindow(at: date(hour: 9)), 60)
    }
}

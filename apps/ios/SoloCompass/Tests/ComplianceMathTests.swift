import XCTest
@testable import SoloCompass

/// City OS v2 §5.2: the visa / 183-day counters are the kit's only
/// self-computed numbers — every boundary is pinned here.
final class ComplianceMathTests: XCTestCase {
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Vientiane")! // UTC+7, no DST
        return cal
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testEntryDayCountsAsDayOne() {
        XCTAssertEqual(ComplianceMath.daysStayed(entryDate: date(2026, 7, 6), now: date(2026, 7, 6), calendar: calendar), 1)
    }

    func testPRDExampleStayedThreeDays() {
        // "落地签 30 天 · 已停留 3 天 · 剩 27 天 · 距 183 天税务线 180 天"
        let entry = date(2026, 7, 4)
        let now = date(2026, 7, 6)
        let stayed = ComplianceMath.daysStayed(entryDate: entry, now: now, calendar: calendar)
        XCTAssertEqual(stayed, 3)
        XCTAssertEqual(ComplianceMath.visaDaysRemaining(entryDate: entry, visaLengthDays: 30, now: now, calendar: calendar), 27)
        XCTAssertEqual(ComplianceMath.taxDaysRemaining(daysStayed: stayed), 180)
    }

    func testCalendarDayBoundaryNotTwentyFourHours() {
        // 23:00 → 01:00 next day is 2 calendar days despite being 2 hours apart.
        let entry = date(2026, 7, 5, hour: 23)
        let now = date(2026, 7, 6, hour: 1)
        XCTAssertEqual(ComplianceMath.daysStayed(entryDate: entry, now: now, calendar: calendar), 2)
    }

    func testFutureEntryDateIsZeroDays() {
        XCTAssertEqual(ComplianceMath.daysStayed(entryDate: date(2026, 8, 1), now: date(2026, 7, 6), calendar: calendar), 0)
    }

    func testOverstayGoesNegative() {
        let entry = date(2026, 6, 1)
        let now = date(2026, 7, 6) // stayed 36 days on a 30-day visa
        XCTAssertEqual(ComplianceMath.visaDaysRemaining(entryDate: entry, visaLengthDays: 30, now: now, calendar: calendar), -6)
    }

    func testTaxDaysFloorAtZero() {
        XCTAssertEqual(ComplianceMath.taxDaysRemaining(daysStayed: 200), 0)
    }

    func testBannerBoundaryAtSeven() {
        XCTAssertTrue(ComplianceMath.shouldShowBanner(daysRemaining: 7))
        XCTAssertFalse(ComplianceMath.shouldShowBanner(daysRemaining: 8))
        XCTAssertTrue(ComplianceMath.shouldShowBanner(daysRemaining: 0))
        XCTAssertTrue(ComplianceMath.shouldShowBanner(daysRemaining: -3)) // overstay stays critical
    }
}

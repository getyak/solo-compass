import XCTest
@testable import SoloCompass

/// Coverage for `Experience.nextBestWindowIsTomorrow(at:)`, which powers the
/// "· tomorrow" tail on the best-time hint pill in ExperienceCardView.
///
/// A bare "Best 7–9am" pill reads the same at 8am (the window opens later today)
/// and at 11pm (every window today has passed, so the hint really means tomorrow
/// morning). This flag lets the card disambiguate the two. These tests pin its
/// boundaries against the *same* window-selection logic `bestTimeHint(at:)` uses,
/// so the flag never disagrees with the range actually shown.
final class BestTimeTomorrowTests: XCTestCase {

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
            id: "tomorrow_fixture",
            title: "Tomorrow Fixture",
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

    /// Single 10–12 window. At 15:00 it has already passed for today, so the only
    /// hint is tomorrow's morning occurrence → flag is true.
    func testAfterTheOnlyWindowClosedIsTomorrow() {
        let exp = Self.makeExp(windows: [TimeWindow(startHour: 10, endHour: 12)])
        XCTAssertTrue(exp.nextBestWindowIsTomorrow(at: date(hour: 15)))
    }

    /// Same window, but at 06:00 it still opens later TODAY, so the hint refers to
    /// today and the flag is false (even though it isn't imminent yet).
    func testBeforeTheWindowOpensIsNotTomorrow() {
        let exp = Self.makeExp(windows: [TimeWindow(startHour: 10, endHour: 12)])
        XCTAssertFalse(exp.nextBestWindowIsTomorrow(at: date(hour: 6)))
    }

    /// While the window is open the experience is best-now, so there is no hint to
    /// qualify and the flag is false (BestNowBadge takes over instead).
    func testBestNowIsNotTomorrow() {
        let exp = Self.makeExp(windows: [TimeWindow(startHour: 10, endHour: 12)])
        XCTAssertTrue(exp.isBestNow(at: date(hour: 11)))
        XCTAssertFalse(exp.nextBestWindowIsTomorrow(at: date(hour: 11)))
    }

    /// With no best times there is no window to wrap, so the flag is false.
    func testEmptyBestTimesIsNotTomorrow() {
        let exp = Self.makeExp(windows: [])
        XCTAssertFalse(exp.nextBestWindowIsTomorrow(at: date(hour: 22)))
    }

    /// Two windows (10–12 and 14–16). At 13:00 the 14:00 window is still ahead
    /// today, so even though the morning one has passed the hint is today → false.
    func testStillAnUpcomingWindowTodayIsNotTomorrow() {
        let exp = Self.makeExp(windows: [
            TimeWindow(startHour: 10, endHour: 12),
            TimeWindow(startHour: 14, endHour: 16),
        ])
        XCTAssertFalse(exp.nextBestWindowIsTomorrow(at: date(hour: 13)))
    }

    /// Both windows have passed by 17:00, so the soonest occurrence is tomorrow's
    /// 10:00 window → true.
    func testBothWindowsPassedIsTomorrow() {
        let exp = Self.makeExp(windows: [
            TimeWindow(startHour: 10, endHour: 12),
            TimeWindow(startHour: 14, endHour: 16),
        ])
        XCTAssertTrue(exp.nextBestWindowIsTomorrow(at: date(hour: 17)))
    }

    /// The flag must agree with the hint: whenever `bestTimeHint` is non-nil and
    /// no window starts later today, the flag is true; otherwise false. Sweep the
    /// clock across the day for a morning-only window to lock the contract.
    func testFlagAgreesWithHintAcrossTheDay() {
        let exp = Self.makeExp(windows: [TimeWindow(startHour: 7, endHour: 9)])
        for hour in 0..<24 {
            let at = date(hour: hour)
            guard exp.bestTimeHint(at: at) != nil else {
                // No hint (best now) ⇒ flag must be false.
                XCTAssertFalse(exp.nextBestWindowIsTomorrow(at: at), "hour \(hour): no hint but flagged tomorrow")
                continue
            }
            let cal = Calendar.current
            let currentHour = cal.component(.hour, from: at)
            let expected = !(7 > currentHour) // window opens later today only when 7 > now
            XCTAssertEqual(
                exp.nextBestWindowIsTomorrow(at: at), expected,
                "hour \(hour): tomorrow flag disagreed with the displayed hint"
            )
        }
    }
}

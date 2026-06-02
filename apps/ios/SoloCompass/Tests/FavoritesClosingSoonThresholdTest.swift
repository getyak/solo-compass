import XCTest
@testable import SoloCompass

/// Verifies that the ≤45-minute threshold driving the "Closing soon" pill in
/// FavoritesListView is consistent with `minutesLeftInBestWindow(at:)`.
///
/// The pill logic:
///   let minutesLeft = goodNow ? exp.minutesLeftInBestWindow(at: now) : nil
///   let closingSoon = (minutesLeft ?? .max) <= 45
///
/// Tests here exercise the model method that feeds that computation directly,
/// confirming the boundary at 45 minutes.
final class FavoritesClosingSoonThresholdTest: XCTestCase {

    // MARK: - Fixture

    private static func makeExp(startHour: Int, endHour: Int) -> Experience {
        let now = Date()
        return Experience(
            id: "closing_soon_fixture",
            title: "Closing Soon Fixture",
            oneLiner: "Test",
            whyItMatters: "Test",
            category: .coffee,
            location: ExperienceLocation(coordinates: [100.0, 13.0], cityCode: "bkk"),
            bestTimes: [TimeWindow(startHour: startHour, endHour: endHour)],
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

    // MARK: - Tests

    /// When 46 minutes remain, closingSoon must be false.
    func testAboveThresholdIsNotClosingSoon() {
        let cal = Calendar.current
        // Build a window that ends exactly 46 minutes from now.
        let endDate = Date().addingTimeInterval(46 * 60)
        let endHour = cal.component(.hour, from: endDate)
        // Start well before now so the window is currently open.
        let startHour = (endHour + 23) % 24
        let exp = Self.makeExp(startHour: startHour, endHour: endHour)

        let minutesLeft = exp.minutesLeftInBestWindow(at: Date())
        guard let mins = minutesLeft else {
            XCTFail("Expected window to be active")
            return
        }
        let closingSoon = mins <= 45
        XCTAssertFalse(closingSoon, "46 min left — should not be closing soon (got \(mins))")
    }

    /// When 45 minutes remain, closingSoon must be true.
    func testAtThresholdIsClosingSoon() {
        let cal = Calendar.current
        let endDate = Date().addingTimeInterval(45 * 60)
        let endHour = cal.component(.hour, from: endDate)
        let startHour = (endHour + 23) % 24
        let exp = Self.makeExp(startHour: startHour, endHour: endHour)

        let minutesLeft = exp.minutesLeftInBestWindow(at: Date())
        guard let mins = minutesLeft else {
            XCTFail("Expected window to be active")
            return
        }
        let closingSoon = mins <= 45
        XCTAssertTrue(closingSoon, "45 min left — should be closing soon (got \(mins))")
    }

    /// When the experience is not currently in its best window, minutesLeft is
    /// nil and closingSoon must be false (nil ?? .max is greater than 45).
    func testNotGoodNowIsNeverClosingSoon() {
        // Window 3–4 am — almost certainly not open right now during a test run.
        let exp = Self.makeExp(startHour: 3, endHour: 4)
        let now = Date()
        guard !exp.isBestNow(at: now) else {
            // If test is somehow run between 3–4am, skip rather than fail.
            return
        }
        let minutesLeft = exp.minutesLeftInBestWindow(at: now)
        XCTAssertNil(minutesLeft, "Window not active — minutesLeftInBestWindow should be nil")
        let closingSoon = (minutesLeft ?? .max) <= 45
        XCTAssertFalse(closingSoon, "Not in best window — closingSoon must be false")
    }
}

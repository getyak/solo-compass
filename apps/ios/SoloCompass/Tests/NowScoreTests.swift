import XCTest
@testable import SoloCompass

/// US-001: `Experience.nowScore(at:)` produces a continuous `[0, 1]` timeliness
/// score. v1 only consults `bestTimes`: in-window → 1.0, out-of-window → 0.0,
/// empty bestTimes → 0.5 (neutral). `isBestNow(at:)` is the `>= 0.7` view of it.
final class NowScoreTests: XCTestCase {

    /// Builds a minimal experience with the supplied bestTimes windows.
    /// Mirrors the fixture shape used by `FilterNowMapSyncTest`/`NowCountCacheTests`.
    private func makeExperience(bestTimes: [TimeWindow]) -> Experience {
        let now = Date()
        return Experience(
            id: "now_score_fixture",
            title: "Fixture",
            oneLiner: "NowScore fixture",
            whyItMatters: "NowScore test fixture",
            category: .coffee,
            location: ExperienceLocation(coordinates: [98.99, 18.79], cityCode: "cmi"),
            bestTimes: bestTimes,
            durationMinutes: .init(min: 30, max: 60),
            howTo: [],
            realInconveniences: [],
            soloScore: SoloScore(
                overall: 5,
                breakdown: .init(
                    seatingFriendly: 7, soloPatronRatio: 7, staffPressure: 7,
                    soloPortioning: 7, ambianceFit: 7, safety: 7
                ),
                basedOnCount: 1
            ),
            sources: [InformationSource(type: .user, attribution: "test", verifiedAt: now)],
            confidence: Confidence(
                level: 4,
                lastVerifiedAt: now,
                reason: "Test fixture",
                signals: .init(aiScrapeAgeDays: 1, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .active,
            createdAt: now,
            updatedAt: now
        )
    }

    /// A fixed date at the given hour, used to make window membership deterministic.
    private func date(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 5
        components.hour = hour
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    func testInWindowScoresOne() {
        let exp = makeExperience(bestTimes: [TimeWindow(startHour: 9, endHour: 17)])
        let score = exp.nowScore(at: date(hour: 12))
        XCTAssertEqual(score.value, 1.0, accuracy: 0.0001)
        XCTAssertTrue(exp.isBestNow(at: date(hour: 12)))
    }

    func testOutOfWindowScoresZero() {
        let exp = makeExperience(bestTimes: [TimeWindow(startHour: 9, endHour: 17)])
        let score = exp.nowScore(at: date(hour: 22))
        XCTAssertEqual(score.value, 0.0, accuracy: 0.0001)
        XCTAssertFalse(exp.isBestNow(at: date(hour: 22)))
    }

    func testEmptyBestTimesScoresNeutralHalf() {
        let exp = makeExperience(bestTimes: [])
        let score = exp.nowScore(at: date(hour: 12))
        XCTAssertEqual(score.value, 0.5, accuracy: 0.0001)
        // 0.5 < 0.7, so isBestNow stays false for empty bestTimes (unchanged behavior).
        XCTAssertFalse(exp.isBestNow(at: date(hour: 12)))
    }
}

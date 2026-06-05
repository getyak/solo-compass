import Foundation
@testable import SoloCompass

/// Shared fixtures for the US-004 NowScoreEngine degradation tests, mirroring the
/// minimal-experience shape used by `NowScoreTests`.
enum NowScoreTestSupport {

    /// Builds a minimal experience with the supplied bestTimes windows.
    static func makeExperience(bestTimes: [TimeWindow]) -> Experience {
        let now = Date()
        return Experience(
            id: "now_score_engine_fixture",
            title: "Fixture",
            oneLiner: "NowScoreEngine fixture",
            whyItMatters: "NowScoreEngine test fixture",
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
    static func date(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 5
        components.hour = hour
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }
}

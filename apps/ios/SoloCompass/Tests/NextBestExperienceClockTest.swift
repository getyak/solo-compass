import XCTest
import CoreLocation
import SwiftData
@testable import SoloCompass

/// Verifies that `nextBestExperience(now:)` accepts an injectable clock so
/// the "Now" filter empty-state countdown can be driven by `TimelineView`
/// and stays unit-testable without real wall-clock dependencies.
@MainActor
final class NextBestExperienceClockTest: XCTestCase {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "nexbest.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        ud.removePersistentDomain(forName: suite)
        return ud
    }

    /// Build an experience whose best window starts `startHour`..`endHour` (local).
    private func makeExperience(id: String, startHour: Int, endHour: Int) -> Experience {
        let now = Date()
        return Experience(
            id: id,
            title: "Clock Fixture \(id)",
            oneLiner: "fixture",
            whyItMatters: "clock test fixture",
            category: .nature,
            location: ExperienceLocation(coordinates: [98.99, 18.79], cityCode: "cmi"),
            bestTimes: [TimeWindow(startHour: startHour, endHour: endHour)],
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
                level: 3,
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

    private func makeViewModel(seed: [Experience]) -> MapViewModel {
        let prefs = UserPreferences(defaults: makeIsolatedDefaults())
        let repo = ExperienceRepository(
            context: ModelContext(SoloCompassModelContainer.makeInMemory()),
            preferences: nil
        )
        _ = repo.appendGenerated(seed)
        let service = ExperienceService(seed: seed, repository: repo)
        let vm = MapViewModel(
            locationService: LocationService(),
            experienceService: service,
            aiService: AIService(),
            preferences: prefs
        )
        vm.selectedCity = "cmi"
        vm.isNowFilter = true
        return vm
    }

    /// Given a fixed `now` that is before the experience's start hour,
    /// `nextBestExperience(now:)` returns the correct experience and a
    /// positive `minutesUntil`. A second call with `now + 1 min` returns
    /// a value that is 1 minute smaller (the countdown decrements).
    func testMinutesUntilDecrementsWithInjectableNow() throws {
        let cal = Calendar.current

        // Pin `now` to 07:30 local so startHour 9 is reliably in the future.
        var components = cal.dateComponents([.year, .month, .day], from: Date())
        components.hour = 7
        components.minute = 30
        components.second = 0
        let baseNow = try XCTUnwrap(cal.date(from: components))

        let exp = makeExperience(id: "sunrise_walk", startHour: 9, endHour: 11)
        let vm = makeViewModel(seed: [exp])

        let result1 = try XCTUnwrap(vm.nextBestExperience(now: baseNow))
        XCTAssertEqual(result1.experience.id, "sunrise_walk")
        XCTAssert(result1.minutesUntil > 0, "minutesUntil must be positive when start is in the future")
        XCTAssert(result1.minutesUntil <= 180, "must be within the 180-minute window")

        // Advance by 1 minute — the countdown must be exactly 1 less.
        let oneMinuteLater = baseNow.addingTimeInterval(60)
        let result2 = try XCTUnwrap(vm.nextBestExperience(now: oneMinuteLater))
        XCTAssertEqual(result2.minutesUntil, result1.minutesUntil - 1,
                       "each successive minute must decrement minutesUntil by 1")

        // Advance by 10 more minutes.
        let tenMinutesLater = baseNow.addingTimeInterval(600)
        let result3 = try XCTUnwrap(vm.nextBestExperience(now: tenMinutesLater))
        XCTAssertEqual(result3.minutesUntil, result1.minutesUntil - 10,
                       "10-minute advance must decrement minutesUntil by 10")
    }

    /// When `now` is inside the best window (experience is already at its best),
    /// `nextBestExperience(now:)` must not return that experience.
    func testReturnsNilWhenExperienceIsCurrentlyAtBest() throws {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: Date())
        // Pin to 10:00 — inside the 9..11 window.
        components.hour = 10
        components.minute = 0
        components.second = 0
        let insideWindow = try XCTUnwrap(cal.date(from: components))

        let exp = makeExperience(id: "peak_now", startHour: 9, endHour: 11)
        let vm = makeViewModel(seed: [exp])

        // The experience is isBestNow at this time, so it should be filtered out.
        XCTAssertNil(vm.nextBestExperience(now: insideWindow),
                     "nextBestExperience must return nil when the only candidate is already at its best")
    }
}

import XCTest
import CoreLocation
import SwiftData
@testable import SoloCompass

/// Verifies `soonestUpcomingExperience(now:)` — the uncapped sibling of
/// `nextBestExperience(now:)` that powers the "Now" filter's dedicated empty
/// state (`NowEmptyOverlay`). Where `nextBestExperience` caps at 180 minutes
/// to drive the imminent countdown capsule, this helper must surface the
/// soonest worthwhile window *however far out it is today*, so the quiet-hours
/// overlay can point the traveler at "next best · Café X · 5–7pm" instead of a
/// generic clear-filters dead-end.
@MainActor
final class SoonestUpcomingExperienceTests: XCTestCase {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "soonest.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        ud.removePersistentDomain(forName: suite)
        return ud
    }

    private func makeExperience(id: String, startHour: Int, endHour: Int) -> Experience {
        let now = Date()
        return Experience(
            id: id,
            title: "Soonest Fixture \(id)",
            oneLiner: "fixture",
            whyItMatters: "soonest test fixture",
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

    private func date(hour: Int, minute: Int) throws -> Date {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return try XCTUnwrap(cal.date(from: components))
    }

    /// The core distinction: a window that opens later today but >180 min out
    /// is invisible to `nextBestExperience` yet must be surfaced here, so the
    /// overlay can still recommend it during the afternoon/evening lull.
    func testSurfacesWindowBeyond180MinuteCap() throws {
        // 08:00 now; best window 18:00–20:00 → 600 min away (well past 180).
        let baseNow = try date(hour: 8, minute: 0)
        let exp = makeExperience(id: "evening_market", startHour: 18, endHour: 20)
        let vm = makeViewModel(seed: [exp])

        // The capped helper sees nothing this far out.
        XCTAssertNil(vm.nextBestExperience(now: baseNow),
                     "nextBestExperience must ignore a window more than 180 minutes away")

        // The uncapped helper still points at it.
        let result = try XCTUnwrap(vm.soonestUpcomingExperience(now: baseNow),
                                   "soonestUpcomingExperience must surface a later-today window")
        XCTAssertEqual(result.experience.id, "evening_market")
        XCTAssertEqual(result.minutesUntil, 600, "18:00 is 600 minutes after 08:00")
    }

    /// With several future windows, the soonest one wins regardless of order.
    func testPicksTheSoonestAmongMultiple() throws {
        let baseNow = try date(hour: 7, minute: 0)
        let later = makeExperience(id: "late", startHour: 19, endHour: 21)   // 720 min
        let sooner = makeExperience(id: "soon", startHour: 12, endHour: 14)  // 300 min
        let vm = makeViewModel(seed: [later, sooner])

        let result = try XCTUnwrap(vm.soonestUpcomingExperience(now: baseNow))
        XCTAssertEqual(result.experience.id, "soon", "the nearest future window must win")
        XCTAssertEqual(result.minutesUntil, 300)
    }

    /// Already at its best → not "upcoming"; excluded from the result.
    func testExcludesExperienceAlreadyAtBest() throws {
        let insideWindow = try date(hour: 10, minute: 0)   // inside 9..11
        let exp = makeExperience(id: "peak_now", startHour: 9, endHour: 11)
        let vm = makeViewModel(seed: [exp])

        XCTAssertNil(vm.soonestUpcomingExperience(now: insideWindow),
                     "an experience currently at its best is not an upcoming window")
    }

    /// Genuinely late night with no further windows today → nil, which is the
    /// overlay's signal to show the "best times resume tomorrow" copy.
    func testReturnsNilWhenNothingOpensAgainToday() throws {
        // 23:30 now; the only window (9..11) is long past for today.
        let lateNight = try date(hour: 23, minute: 30)
        let exp = makeExperience(id: "morning_only", startHour: 9, endHour: 11)
        let vm = makeViewModel(seed: [exp])

        XCTAssertNil(vm.soonestUpcomingExperience(now: lateNight),
                     "no remaining window today must return nil")
    }
}

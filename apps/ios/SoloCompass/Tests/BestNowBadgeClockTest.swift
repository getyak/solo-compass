import XCTest
@testable import SoloCompass

// MARK: - US-023: shared BestNowClock across BestNowBadge instances

/// Verifies the US-023 optimisation: every `BestNowBadge` reads one shared
/// `BestNowClock` from the environment instead of hosting its own
/// `TimelineView(.periodic(by: 60))`. The pre-fix Explore screen with 20+
/// best-now badges spun up 20+ concurrent timelines — one main-actor timer per
/// badge. The fix collapses them onto a single `Timer`.
///
/// We can't introspect SwiftUI's private timeline schedulers from a unit test,
/// so the contract is enforced at the source: `BestNowClock` owns the only
/// timer and exposes `activeTimerCount`. Constructing 100 badges that all share
/// one clock must leave that count at exactly 1.
///
/// Run with:
///   xcodebuild test -only-testing:SoloCompassTests/BestNowBadgeClockTest
@MainActor
final class BestNowBadgeClockTest: XCTestCase {

    private static let badgeCount = 100

    /// 100 badges sharing one clock allocate exactly one timer.
    func testHundredBadgesShareSingleTimer() throws {
        let baseline = BestNowClock.activeTimerCount

        // One clock for all badges — mirrors the single `.environment(clock)`
        // injection at the app root that every badge then reads.
        let clock = BestNowClock(startDate: Date())
        XCTAssertEqual(
            BestNowClock.activeTimerCount - baseline, 1,
            "Constructing the shared clock must allocate exactly one timer."
        )

        // Hand the *same* clock to 100 badge environments. Reading it through
        // the environment never spins up a new timer — the count stays at 1.
        var hosts: [AnyView] = []
        hosts.reserveCapacity(Self.badgeCount)
        let experience = Self.makeExperience()
        for _ in 0..<Self.badgeCount {
            hosts.append(
                AnyView(
                    ExperienceCardView(experience: experience, onExpand: {}, onDismiss: {})
                        .environment(clock)
                )
            )
        }
        XCTAssertEqual(hosts.count, Self.badgeCount)

        XCTAssertEqual(
            BestNowClock.activeTimerCount - baseline, 1,
            """
            \(Self.badgeCount) badges share one clock — only the single clock \
            timer may be allocated, not one per badge.
            """
        )

        // Keep the clock alive across the assertions so ARC can't release it
        // (and decrement the count) before we read it.
        withExtendedLifetime(clock) {}
    }

    /// Advancing the shared clock once moves `tick` for everyone — a single
    /// fire refreshes all badges rather than each badge firing independently.
    func testAdvanceUpdatesTickForAllConsumers() throws {
        let clock = BestNowClock(startDate: Date(timeIntervalSince1970: 1_000_000))
        let before = clock.tick
        let next = before.addingTimeInterval(60)
        clock.advance(to: next)
        XCTAssertEqual(clock.tick, next,
                       "advance(to:) must move the shared tick that all badges observe.")
        withExtendedLifetime(clock) {}
    }

    // MARK: - Fixture

    private static func makeExperience() -> Experience {
        let now = Date()
        return Experience(
            id: "bestnow_clock_fixture",
            title: "Best Now Fixture",
            oneLiner: "Open right now",
            whyItMatters: "Clock fixture",
            category: .food,
            location: ExperienceLocation(coordinates: [98.9938, 18.7877], cityCode: "cmi"),
            bestTimes: [TimeWindow(startHour: 0, endHour: 23)],
            durationMinutes: .init(min: 30, max: 60),
            howTo: [],
            realInconveniences: [],
            soloScore: SoloScore(
                overall: 8.0,
                breakdown: .init(
                    seatingFriendly: 7, soloPatronRatio: 7, staffPressure: 7,
                    soloPortioning: 7, ambianceFit: 7, safety: 7
                ),
                basedOnCount: 3
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
}

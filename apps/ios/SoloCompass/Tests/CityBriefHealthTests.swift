import XCTest
@testable import SoloCompass

/// City OS v2: pins the client-side freshness rules for kit rows and events —
/// health decay thresholds (mirroring `Confidence.health`), event expiry, and
/// the deterministic 今日城市签 daily pick.
final class CityBriefHealthTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000) // fixed clock

    private func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 86_400)
    }

    // MARK: - health(lastVerifiedAt:serverHealth:now:)

    func testNilLastVerifiedIsQuestioned() {
        XCTAssertEqual(CityBriefHealth.health(lastVerifiedAt: nil, serverHealth: "green", now: now), .questioned)
    }

    func testFreshGreenIsHealthy() {
        XCTAssertEqual(CityBriefHealth.health(lastVerifiedAt: daysAgo(2), serverHealth: "green", now: now), .healthy)
    }

    func testFreshYellowIsFading() {
        XCTAssertEqual(CityBriefHealth.health(lastVerifiedAt: daysAgo(2), serverHealth: "yellow", now: now), .fading)
    }

    func testFreshRedIsQuestioned() {
        XCTAssertEqual(CityBriefHealth.health(lastVerifiedAt: daysAgo(2), serverHealth: "red", now: now), .questioned)
    }

    func testFreshGrayDefaultsToFading() {
        XCTAssertEqual(CityBriefHealth.health(lastVerifiedAt: daysAgo(2), serverHealth: "gray", now: now), .fading)
        XCTAssertEqual(CityBriefHealth.health(lastVerifiedAt: daysAgo(2), serverHealth: nil, now: now), .fading)
    }

    func testStaleGreenIsCappedAtFading() {
        // 30–60 days: staleness can only downgrade the server floor.
        XCTAssertEqual(CityBriefHealth.health(lastVerifiedAt: daysAgo(45), serverHealth: "green", now: now), .fading)
    }

    func testStaleRedStaysQuestioned() {
        XCTAssertEqual(CityBriefHealth.health(lastVerifiedAt: daysAgo(45), serverHealth: "red", now: now), .questioned)
    }

    func testOlderThanSixtyDaysIsMayBeGone() {
        // Same cliff as Confidence.health, regardless of server floor.
        XCTAssertEqual(CityBriefHealth.health(lastVerifiedAt: daysAgo(61), serverHealth: "green", now: now), .mayBeGone)
    }

    // MARK: - isExpired

    private func event(id: String = "evt_vte_test_20260706", starts: Date? = nil, ends: Date? = nil, solo: Double? = nil, category: String? = "market") -> CityEvent {
        CityEvent(id: id, cityCode: "vte", name: "测试事件", whenLabel: "本周", startsAt: starts, endsAt: ends, soloScore: solo, category: category)
    }

    func testEventPastEndsAtIsExpired() {
        XCTAssertTrue(CityBriefHealth.isExpired(event(ends: daysAgo(0.1)), now: now))
    }

    func testEventBeforeEndsAtIsNotExpired() {
        XCTAssertFalse(CityBriefHealth.isExpired(event(ends: now.addingTimeInterval(3_600)), now: now))
    }

    func testNilEndsAtFallsBackToStartsPlusOneDay() {
        XCTAssertTrue(CityBriefHealth.isExpired(event(starts: daysAgo(2), ends: nil), now: now))
        XCTAssertFalse(CityBriefHealth.isExpired(event(starts: daysAgo(0.5), ends: nil), now: now))
    }

    func testEventWithNoDatesIsKept() {
        XCTAssertFalse(CityBriefHealth.isExpired(event(starts: nil, ends: nil), now: now))
    }

    // MARK: - dailyPick

    func testDailyPickPrefersHighestSoloScore() {
        let events = [
            event(id: "evt_a", ends: now.addingTimeInterval(86_400), solo: 7.0),
            event(id: "evt_b", ends: now.addingTimeInterval(86_400), solo: 9.0),
        ]
        XCTAssertEqual(CityBriefHealth.dailyPick(from: events, now: now)?.id, "evt_b")
    }

    func testDailyPickExcludesNoticesAndExpired() {
        let events = [
            event(id: "evt_notice", ends: now.addingTimeInterval(86_400), solo: nil, category: "notice"),
            event(id: "evt_gone", ends: daysAgo(1), solo: 9.9),
        ]
        XCTAssertNil(CityBriefHealth.dailyPick(from: events, now: now))
    }

    func testDailyPickIsDeterministicWithinADay() {
        // Tied scores resolve via the stable hash — same inputs, same pick,
        // in whatever order the events arrive.
        let a = event(id: "evt_a", ends: now.addingTimeInterval(86_400), solo: 8.0)
        let b = event(id: "evt_b", ends: now.addingTimeInterval(86_400), solo: 8.0)
        let pick1 = CityBriefHealth.dailyPick(from: [a, b], now: now)?.id
        let pick2 = CityBriefHealth.dailyPick(from: [b, a], now: now)?.id
        XCTAssertNotNil(pick1)
        XCTAssertEqual(pick1, pick2)
    }

    func testStableHashIsProcessIndependent() {
        // FNV-1a of "a" must always be the same constant — this is what makes
        // the daily pick reproducible across launches.
        XCTAssertEqual(CityBriefHealth.stableHash("a"), 0xaf63dc4c8601ec8c)
    }

    func testEmptyEventsYieldNoPick() {
        XCTAssertNil(CityBriefHealth.dailyPick(from: [], now: now))
    }
}

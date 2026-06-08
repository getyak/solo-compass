import XCTest
@testable import SoloCompass

/// US-016: anti-abuse gate for discover-sourced friend adds.
final class DiscoverFriendGateTests: XCTestCase {
    private let gate = DiscoverFriendGate(maxPerWindow: 3, window: 3600)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Reporter-weight floor (≥ 0.3)

    func testAllowsAuthorAtOrAboveFloor() {
        XCTAssertNil(gate.evaluate(reporterWeight: 0.3, recentAddTimestamps: [], now: now))
        XCTAssertNil(gate.evaluate(reporterWeight: 1.0, recentAddTimestamps: [], now: now))
    }

    func testDeniesAuthorBelowFloor() {
        XCTAssertEqual(
            gate.evaluate(reporterWeight: 0.29, recentAddTimestamps: [], now: now),
            .lowReporterWeight
        )
        XCTAssertEqual(
            gate.evaluate(reporterWeight: 0.0, recentAddTimestamps: [], now: now),
            .lowReporterWeight
        )
    }

    func testFloorMatchesDiscoveryThreshold() {
        XCTAssertEqual(DiscoverFriendGate.reporterWeightFloor, companionReporterWeightThreshold)
        XCTAssertEqual(DiscoverFriendGate.reporterWeightFloor, 0.3, accuracy: 0.0001)
    }

    // MARK: - Rate limit (rolling window)

    func testAllowsUnderRateLimit() {
        let recent = [now.addingTimeInterval(-60), now.addingTimeInterval(-120)]
        XCTAssertNil(gate.evaluate(reporterWeight: 0.9, recentAddTimestamps: recent, now: now))
    }

    func testDeniesAtRateLimit() {
        let recent = [
            now.addingTimeInterval(-60),
            now.addingTimeInterval(-120),
            now.addingTimeInterval(-180),
        ]
        XCTAssertEqual(
            gate.evaluate(reporterWeight: 0.9, recentAddTimestamps: recent, now: now),
            .rateLimited
        )
    }

    func testTimestampsOutsideWindowDoNotCount() {
        // Three adds, but all older than the 1h window → not rate limited.
        let stale = [
            now.addingTimeInterval(-3700),
            now.addingTimeInterval(-7200),
            now.addingTimeInterval(-9000),
        ]
        XCTAssertNil(gate.evaluate(reporterWeight: 0.9, recentAddTimestamps: stale, now: now))
    }

    // MARK: - Precedence

    func testReporterWeightCheckedBeforeRateLimit() {
        // Below floor AND over limit → reports the trust failure first.
        let recent = Array(repeating: now.addingTimeInterval(-60), count: 5)
        XCTAssertEqual(
            gate.evaluate(reporterWeight: 0.1, recentAddTimestamps: recent, now: now),
            .lowReporterWeight
        )
    }
}

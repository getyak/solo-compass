import XCTest
@testable import SoloCompass

/// US-007: the best-now badge renders a one-line NowScore reason subtitle.
///
/// The composition rule — top-3 contributing signals by weight × value, joined
/// with ` · `, ellipsized past 28 characters — lives in two pure functions:
/// `Experience.composeNowScore` (orders reasons by strength) and
/// `Experience.nowReasonSubtitle` (top-3 + truncation). These tests snapshot the
/// short / medium / truncated cases end-to-end through both.
final class BestNowBadgeReasonTests: XCTestCase {

    private func contribution(_ value: Double, weight: Double, reason: String?)
        -> NowSignalContribution {
        NowSignalContribution(value: value, weight: weight, reason: reason)
    }

    // MARK: - Snapshot: short reason (1 signal)

    func testShortReasonSingleSignal() {
        let score = Experience.composeNowScore(from: [
            ("bestTimes", contribution(1.0, weight: 0.4, reason: "晴")),
        ])
        XCTAssertEqual(Experience.nowReasonSubtitle(for: score), "晴")
    }

    // MARK: - Snapshot: medium reason (2 signals)

    func testMediumReasonTwoSignals() {
        let score = Experience.composeNowScore(from: [
            ("bestTimes", contribution(1.0, weight: 0.4, reason: "日落 23 分钟后")),
            ("weather", contribution(1.0, weight: 0.2, reason: "晴")),
        ])
        // bestTimes strength 0.4 > weather strength 0.2 → leads the subtitle.
        XCTAssertEqual(Experience.nowReasonSubtitle(for: score), "日落 23 分钟后 · 晴")
    }

    // MARK: - Snapshot: long reason requiring truncation

    func testLongReasonTruncatesAt28Chars() {
        let long = "This is a deliberately long weather reason"
        let score = Experience.composeNowScore(from: [
            ("weather", contribution(1.0, weight: 0.4, reason: long)),
        ])
        let subtitle = Experience.nowReasonSubtitle(for: score)
        XCTAssertNotNil(subtitle)
        XCTAssertEqual(subtitle?.count, 28, "27 retained chars + ellipsis = 28")
        XCTAssertTrue(subtitle?.hasSuffix("…") ?? false)
        XCTAssertEqual(subtitle, String(long.prefix(27)) + "…")
    }

    // MARK: - Composition rule details

    func testKeepsOnlyTopThreeSignalsByStrength() {
        let score = Experience.composeNowScore(from: [
            ("a", contribution(1.0, weight: 0.1, reason: "d")),  // strength 0.10
            ("b", contribution(1.0, weight: 0.4, reason: "a")),  // strength 0.40
            ("c", contribution(1.0, weight: 0.3, reason: "b")),  // strength 0.30
            ("e", contribution(1.0, weight: 0.2, reason: "c")),  // strength 0.20
        ])
        // Sorted by weight × value desc → a, b, c, d; only top-3 kept.
        XCTAssertEqual(Experience.nowReasonSubtitle(for: score), "a · b · c")
    }

    func testNilWhenNoReasonSoCallerCanFallBack() {
        let score = Experience.composeNowScore(from: [
            ("bestTimes", contribution(1.0, weight: 0.4, reason: nil)),
        ])
        XCTAssertNil(Experience.nowReasonSubtitle(for: score))
    }

    // MARK: - Badge fallback wiring

    func testBadgeFallsBackToLocalizedLabelWhenReasonMissing() {
        let score = NowScore(value: 0.9, reason: nil, breakdown: [:])
        let subtitle = BestNowBadge.reasonSubtitle(for: score)
        XCTAssertEqual(subtitle, NSLocalizedString("badge.now.fallback", comment: ""))
    }
}

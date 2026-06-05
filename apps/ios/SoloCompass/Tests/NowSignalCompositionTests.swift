import XCTest
@testable import SoloCompass

/// US-002: `Experience.nowScore(at:)` composes registered `NowSignal`s into a
/// weight-normalized average, concatenating each signal's reason with ` · `.
/// These tests exercise the composition math directly via `composeNowScore`,
/// plus the two shipped signals (`bestTimes` × 0.4, `hourOfDay` × 0.2).
final class NowSignalCompositionTests: XCTestCase {

    private let bestKey = BestTimesSignal.key      // "bestTimes", weight 0.4
    private let hourKey = HourOfDaySignal.key      // "hourOfDay", weight 0.2
    private let bestWeight = BestTimesSignal.weight
    private let hourWeight = HourOfDaySignal.weight

    private func contribution(_ value: Double, weight: Double, reason: String?)
        -> NowSignalContribution {
        NowSignalContribution(value: value, weight: weight, reason: reason)
    }

    func testBothSignalsMaxComposeToOne() {
        let score = Experience.composeNowScore(from: [
            (bestKey, contribution(1.0, weight: bestWeight, reason: "a")),
            (hourKey, contribution(1.0, weight: hourWeight, reason: "b")),
        ])
        XCTAssertEqual(score.value, 1.0, accuracy: 0.0001)
    }

    func testOnlyBestTimesMaxApproximatesItsWeightShare() {
        let score = Experience.composeNowScore(from: [
            (bestKey, contribution(1.0, weight: bestWeight, reason: "a")),
            (hourKey, contribution(0.0, weight: hourWeight, reason: "b")),
        ])
        // Weight-normalized share of bestTimes: 0.4 / (0.4 + 0.2) ≈ 0.667.
        let expectedShare = bestWeight / (bestWeight + hourWeight)
        XCTAssertEqual(score.value, expectedShare, accuracy: 0.0001)
    }

    func testOnlyHourOfDayMaxApproximatesItsWeightShare() {
        let score = Experience.composeNowScore(from: [
            (bestKey, contribution(0.0, weight: bestWeight, reason: "a")),
            (hourKey, contribution(1.0, weight: hourWeight, reason: "b")),
        ])
        let expectedShare = hourWeight / (bestWeight + hourWeight)
        XCTAssertEqual(score.value, expectedShare, accuracy: 0.0001)
    }

    func testBothZeroComposeToZero() {
        let score = Experience.composeNowScore(from: [
            (bestKey, contribution(0.0, weight: bestWeight, reason: "a")),
            (hourKey, contribution(0.0, weight: hourWeight, reason: "b")),
        ])
        XCTAssertEqual(score.value, 0.0, accuracy: 0.0001)
    }

    func testReasonsConcatenatedWithMiddot() {
        let score = Experience.composeNowScore(from: [
            (bestKey, contribution(1.0, weight: bestWeight, reason: "in bestTimes window")),
            (hourKey, contribution(1.0, weight: hourWeight, reason: "at ideal hour")),
        ])
        XCTAssertEqual(score.reason, "in bestTimes window · at ideal hour")
    }

    func testEmptySignalListYieldsNeutralHalf() {
        let score = Experience.composeNowScore(from: [])
        XCTAssertEqual(score.value, 0.5, accuracy: 0.0001)
    }

    func testBreakdownCarriesEachSignalValue() {
        let score = Experience.composeNowScore(from: [
            (bestKey, contribution(1.0, weight: bestWeight, reason: "a")),
            (hourKey, contribution(0.0, weight: hourWeight, reason: "b")),
        ])
        XCTAssertEqual(score.breakdown[bestKey], 1.0)
        XCTAssertEqual(score.breakdown[hourKey], 0.0)
    }
}

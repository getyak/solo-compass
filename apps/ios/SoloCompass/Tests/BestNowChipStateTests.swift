import XCTest
import SwiftUI
@testable import SoloCompass

/// Unit coverage for `BestNowChipState` — the shared "此刻最佳 / Closing soon"
/// chip model used by `PeekSummaryCard` and `NearbyExperienceRow`.
///
/// The chip flips to its amber countdown form once the active best-time window
/// has ≤ 45 minutes left, matching `BestNowBadge` and the Saved-list pill. These
/// tests pin the boundary, the visual switch (symbol / tint), the label/a11y
/// formatting, and that both shipped locales carry the new keys.
final class BestNowChipStateTests: XCTestCase {

    // MARK: - Fixture

    /// Experience whose single best-time window is [startHour, endHour).
    private static func makeExp(startHour: Int, endHour: Int) -> Experience {
        let now = Date()
        return Experience(
            id: "best_now_chip_fixture",
            title: "Chip Fixture",
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

    /// Deterministic wall-clock instant expressed in the same `Calendar.current`
    /// the model uses, so these boundary tests don't depend on when CI runs.
    private static func date(hour: Int, minute: Int = 0) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour
        c.minute = minute
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    // MARK: - Threshold

    func testNotOpenYieldsNilMinutes() {
        // 3–4am window, evaluated at noon — never open.
        let exp = Self.makeExp(startHour: 3, endHour: 4)
        let state = BestNowChipState.resolve(for: exp, at: Self.date(hour: 12))
        XCTAssertNil(state.minutesLeft, "Window not active → no minutes")
        XCTAssertFalse(state.isClosingSoon, "Not open → never closing soon")
    }

    func testWellWithinWindowIsNotClosingSoon() {
        // Window 9–17, evaluated at 10:00 → 7h (420 min) left, comfortably
        // above the 45-min threshold.
        let exp = Self.makeExp(startHour: 9, endHour: 17)
        let state = BestNowChipState.resolve(for: exp, at: Self.date(hour: 10))
        // Window is open …
        XCTAssertNotNil(state.minutesLeft)
        XCTAssertFalse(state.isClosingSoon, "7h left should not be closing soon")
    }

    func testInsideThresholdIsClosingSoon() {
        // Window 9–10, evaluated at 09:40 → 20 min left.
        let exp = Self.makeExp(startHour: 9, endHour: 10)
        let state = BestNowChipState.resolve(for: exp, at: Self.date(hour: 9, minute: 40))
        guard let mins = state.minutesLeft else {
            return XCTFail("Expected an active window with minutes left")
        }
        XCTAssertLessThanOrEqual(mins, BestNowChipState.closingSoonThresholdMinutes)
        XCTAssertTrue(state.isClosingSoon, "20 min left should be closing soon (got \(mins))")
    }

    // MARK: - Visual switch

    func testClosingSoonUsesAmberAlarmGlyph() {
        let closing = BestNowChipState(isClosingSoon: true, minutesLeft: 10)
        XCTAssertEqual(closing.symbol, "clock.badge.exclamationmark")
        XCTAssertEqual(closing.foreground, BestNowChipState.amber)

        let calm = BestNowChipState(isClosingSoon: false, minutesLeft: 180)
        XCTAssertEqual(calm.symbol, "sparkles")
        XCTAssertEqual(calm.foreground, CT.sunGoldDeep)
    }

    // MARK: - Label formatting

    func testClosingSoonLabelEmbedsMinutes() {
        let state = BestNowChipState(isClosingSoon: true, minutesLeft: 12)
        XCTAssertTrue(state.label.contains("12"),
                      "Closing-soon label should embed the minute count, got: \(state.label)")
        XCTAssertTrue(state.accessibilityLabel.contains("12"),
                      "Closing-soon a11y label should embed the minute count")
    }

    func testPlainLabelWhenNotClosingSoon() {
        let state = BestNowChipState(isClosingSoon: false, minutesLeft: 180)
        XCTAssertEqual(state.label,
                       NSLocalizedString("nearby.chip.bestNow", comment: ""),
                       "Non-closing chip should read the plain Best-now label")
    }

    /// A closing-soon state with no known minute count must not crash and falls
    /// back to the plain best-now label (defensive: minutesLeft nil + isClosingSoon
    /// can't arise from `resolve`, but the struct is public-shaped).
    func testClosingSoonWithoutMinutesFallsBackToPlainLabel() {
        let state = BestNowChipState(isClosingSoon: true, minutesLeft: nil)
        XCTAssertEqual(state.label, NSLocalizedString("nearby.chip.bestNow", comment: ""))
    }

    // MARK: - Localization parity

    func testClosingSoonKeysResolveInBothLocales() throws {
        for lang in ["en", "zh-Hans"] {
            // The `.lproj` tables ship in the app bundle (the unit-test host),
            // not the test bundle — search both, matching StringsParityTests /
            // EmptyStateAnnouncementTest. `Bundle(for:)` alone returns nil here.
            let bundleURL = [Bundle.main, Bundle(for: Self.self)]
                .lazy
                .compactMap { $0.url(forResource: lang, withExtension: "lproj") }
                .first
            let resolvedURL = try XCTUnwrap(
                bundleURL,
                "missing \(lang).lproj in the app or test bundle"
            )
            let bundle = try XCTUnwrap(Bundle(url: resolvedURL))
            for key in ["nearby.chip.closingSoon", "nearby.chip.closingSoon.a11y"] {
                let value = bundle.localizedString(forKey: key, value: "__MISSING__", table: nil)
                XCTAssertNotEqual(value, "__MISSING__", "\(key) missing in \(lang)")
                XCTAssertTrue(value.contains("%d"),
                              "\(key) in \(lang) must keep the %d minutes placeholder")
            }

            // US-049: the map marker's closing-soon VoiceOver phrase. Unlike the
            // chip keys above it carries no minute count (the pin shows a glyph,
            // not a countdown), so it must resolve but must NOT contain "%d".
            let markerKey = "marker.a11y.closingSoon"
            let markerValue = bundle.localizedString(forKey: markerKey, value: "__MISSING__", table: nil)
            XCTAssertNotEqual(markerValue, "__MISSING__", "\(markerKey) missing in \(lang)")
            XCTAssertFalse(markerValue.contains("%d"),
                           "\(markerKey) in \(lang) must not embed a minute placeholder")
        }
    }
}

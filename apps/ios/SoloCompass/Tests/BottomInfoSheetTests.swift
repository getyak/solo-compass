import XCTest
@testable import SoloCompass

final class BottomInfoSheetTests: XCTestCase {
    // Fixed instant: 2024-01-15 14:05:00 UTC
    private let fixedDate: Date = {
        var comps = DateComponents()
        comps.year = 2024; comps.month = 1; comps.day = 15
        comps.hour = 14; comps.minute = 5; comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: comps)!
    }()

    func testTimeStringUsLocaleContainsAmPm() {
        let result = NowHintRow.timeString(for: fixedDate, locale: Locale(identifier: "en_US"))
        let lower = result.lowercased()
        XCTAssertTrue(
            lower.contains("am") || lower.contains("pm"),
            "en_US should produce a 12-hour string with AM/PM, got: \(result)"
        )
    }

    func testTimeStringFrFrLocaleIs24Hour() {
        let result = NowHintRow.timeString(for: fixedDate, locale: Locale(identifier: "fr_FR"))
        let lower = result.lowercased()
        XCTAssertFalse(
            lower.contains("am") || lower.contains("pm"),
            "fr_FR should produce a 24-hour string without AM/PM, got: \(result)"
        )
    }

    func testTimeStringEnGbLocaleIs24Hour() {
        let result = NowHintRow.timeString(for: fixedDate, locale: Locale(identifier: "en_GB"))
        let lower = result.lowercased()
        XCTAssertFalse(
            lower.contains("am") || lower.contains("pm"),
            "en_GB should produce a 24-hour string without AM/PM, got: \(result)"
        )
    }

    @MainActor
    func testClockTickAdvancesTimeString() async {
        let clock = BestNowClock(startDate: fixedDate)
        let before = NowHintRow.timeString(for: clock.tick, locale: Locale(identifier: "en_US"))

        var laterComps = DateComponents()
        laterComps.year = 2024; laterComps.month = 1; laterComps.day = 15
        laterComps.hour = 15; laterComps.minute = 6; laterComps.second = 0
        laterComps.timeZone = TimeZone(identifier: "UTC")
        let laterDate = Calendar(identifier: .gregorian).date(from: laterComps)!

        clock.advance(to: laterDate)
        let after = NowHintRow.timeString(for: clock.tick, locale: Locale(identifier: "en_US"))

        XCTAssertNotEqual(before, after, "Time string should change after clock advances")
    }
}

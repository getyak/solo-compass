import XCTest
import CoreLocation
@testable import SoloCompass

/// US-006: `SolarEvents` computes civil sunset/sunrise within ±5 min of known
/// almanac values for two latitude/date fixtures.
final class SolarEventsTests: XCTestCase {

    /// Build a UTC date for the given calendar day (time-of-day irrelevant: the
    /// algorithm keys only off the day-of-year).
    private func utcDay(year: Int, month: Int, day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        return cal.date(from: c)!
    }

    /// Local hour-of-day (as fractional hours) of `instant` in `tz`.
    private func localHours(_ instant: Date, tzIdentifier: String) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tzIdentifier)!
        let c = cal.dateComponents([.hour, .minute], from: instant)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0
    }

    // MARK: - Vientiane (17.97°N, 102.60°E) — summer solstice

    func testVientianeSummerSolsticeSunset() {
        let coord = CLLocationCoordinate2D(latitude: 17.97, longitude: 102.60)
        let date = utcDay(year: 2024, month: 6, day: 21)
        guard let sunset = SolarEvents.sunset(at: coord, on: date) else {
            return XCTFail("Vientiane sunset should exist on the solstice")
        }
        // Almanac: ≈18:50 ICT (UTC+7). Assert within ±5 min.
        let local = localHours(sunset, tzIdentifier: "Asia/Bangkok")
        XCTAssertEqual(local, 18.0 + 50.0 / 60.0, accuracy: 5.0 / 60.0,
                       "Vientiane sunset \(local)h ≠ ~18:50 local")
    }

    // MARK: - Beijing (39.90°N, 116.41°E) — winter solstice

    func testBeijingWinterSolsticeSunset() {
        let coord = CLLocationCoordinate2D(latitude: 39.90, longitude: 116.41)
        let date = utcDay(year: 2024, month: 12, day: 22)
        guard let sunset = SolarEvents.sunset(at: coord, on: date) else {
            return XCTFail("Beijing sunset should exist on the solstice")
        }
        // Almanac: ≈16:50 CST (UTC+8). Assert within ±5 min.
        let local = localHours(sunset, tzIdentifier: "Asia/Shanghai")
        XCTAssertEqual(local, 16.0 + 50.0 / 60.0, accuracy: 5.0 / 60.0,
                       "Beijing sunset \(local)h ≠ ~16:50 local")
    }

    // MARK: - Sunrise sanity (rise precedes set, both on the same day)

    func testSunriseBeforeSunset() {
        let coord = CLLocationCoordinate2D(latitude: 17.97, longitude: 102.60)
        let date = utcDay(year: 2024, month: 6, day: 21)
        let sunrise = SolarEvents.sunrise(at: coord, on: date)
        let sunset = SolarEvents.sunset(at: coord, on: date)
        XCTAssertNotNil(sunrise)
        XCTAssertNotNil(sunset)
        if let r = sunrise, let s = sunset {
            XCTAssertLessThan(localHours(r, tzIdentifier: "Asia/Bangkok"),
                              localHours(s, tzIdentifier: "Asia/Bangkok"))
        }
    }
}

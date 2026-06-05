import Foundation
import CoreLocation

/// Pure-function solar event calculator: civil sunset / sunrise for a coordinate
/// on a given calendar day.
///
/// Implements a simplified form of the NREL Solar Position Algorithm — the
/// low-precision sunrise/sunset equations (accurate to ≈1 min for civil use,
/// well within the ±5 min the product needs). No SPM dependency, no network:
/// everything is closed-form astronomy over the day's day-of-year number.
///
/// All math is done in UTC; callers format into the experience's local time.
/// Returns `nil` for polar day / polar night, where the sun never crosses the
/// horizon and no sunrise/sunset exists.
public enum SolarEvents {

    /// UTC instant the sun's upper limb sets below the horizon on `date`'s day.
    public static func sunset(at coord: CLLocationCoordinate2D, on date: Date) -> Date? {
        event(.sunset, at: coord, on: date)
    }

    /// UTC instant the sun's upper limb rises above the horizon on `date`'s day.
    public static func sunrise(at coord: CLLocationCoordinate2D, on date: Date) -> Date? {
        event(.sunrise, at: coord, on: date)
    }

    // MARK: - Implementation

    private enum Kind { case sunrise, sunset }

    /// Standard zenith for sunrise/sunset = 90°50′ (90.833°): 0°50′ accounts for
    /// the sun's apparent radius plus average atmospheric refraction at the horizon.
    private static let zenith = 90.833 * .pi / 180.0
    private static let deg = Double.pi / 180.0

    private static func event(_ kind: Kind, at coord: CLLocationCoordinate2D, on date: Date) -> Date? {
        // Day number in UTC. Sunrise/sunset eqns key off the day-of-year.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let comps = utc.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return nil }

        let n = dayOfYear(year: year, month: month, day: day)
        let lngHour = coord.longitude / 15.0

        // Approximate event time (in days): rise leans to morning, set to evening.
        let t = (kind == .sunrise)
            ? Double(n) + ((6.0 - lngHour) / 24.0)
            : Double(n) + ((18.0 - lngHour) / 24.0)

        // Sun's mean anomaly → true longitude (degrees).
        let M = (0.9856 * t) - 3.289
        var L = M + (1.916 * sin(M * deg)) + (0.020 * sin(2 * M * deg)) + 282.634
        L = normalize(L, 360)

        // Right ascension, forced into the same quadrant as L.
        var RA = atan(0.91764 * tan(L * deg)) / deg
        RA = normalize(RA, 360)
        let lQuadrant = floor(L / 90.0) * 90.0
        let raQuadrant = floor(RA / 90.0) * 90.0
        RA = (RA + (lQuadrant - raQuadrant)) / 15.0

        // Sun's declination.
        let sinDec = 0.39782 * sin(L * deg)
        let cosDec = cos(asin(sinDec))

        // Local hour angle. |cosH| > 1 ⇒ sun never reaches the horizon today.
        let cosH = (cos(zenith) - (sinDec * sin(coord.latitude * deg)))
            / (cosDec * cos(coord.latitude * deg))
        if cosH > 1 || cosH < -1 { return nil }

        var H = (kind == .sunrise) ? (360.0 - acos(cosH) / deg) : (acos(cosH) / deg)
        H /= 15.0

        // Local mean time of the event, then back to UTC hours.
        let T = H + RA - (0.06571 * t) - 6.622
        let utcHours = normalize(T - lngHour, 24)

        // Compose the UTC instant for that calendar day.
        var midnight = DateComponents()
        midnight.year = year; midnight.month = month; midnight.day = day
        midnight.hour = 0; midnight.minute = 0; midnight.second = 0
        guard let base = utc.date(from: midnight) else { return nil }
        return base.addingTimeInterval(utcHours * 3600.0)
    }

    /// Day-of-year (1-based) for a Gregorian date, leap-year aware.
    private static func dayOfYear(year: Int, month: Int, day: Int) -> Int {
        let cumulative = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
        let leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
        let leapAdj = (leap && month > 2) ? 1 : 0
        return cumulative[month - 1] + day + leapAdj
    }

    /// Wrap `value` into `[0, range)`.
    private static func normalize(_ value: Double, _ range: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: range)
        return r < 0 ? r + range : r
    }
}

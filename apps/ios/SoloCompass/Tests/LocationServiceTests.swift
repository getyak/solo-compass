import XCTest
import CoreLocation
@testable import SoloCompass

// CLHeading is not directly instantiable; subclass to inject test values.
private final class MockHeading: CLHeading {
    private let _trueHeading: CLLocationDirection
    private let _headingAccuracy: CLLocationDirection

    init(trueHeading: CLLocationDirection, accuracy: CLLocationDirection = 5) {
        self._trueHeading = trueHeading
        self._headingAccuracy = accuracy
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("not used in tests") }

    override var trueHeading: CLLocationDirection { _trueHeading }
    override var headingAccuracy: CLLocationDirection { _headingAccuracy }
}

@MainActor
final class LocationServiceTests: XCTestCase {

    // Tokyo Station as the "current" location, Senso-ji as the target.
    // Great-circle bearing Tokyo Station → Senso-ji ≈ 13.8° (roughly north-northeast).
    private let tokyoStation = CLLocation(latitude: 35.6812, longitude: 139.7671)
    private let sensoji = CLLocationCoordinate2D(latitude: 35.7148, longitude: 139.7967)

    // MARK: - Absolute fallback when no heading

    func test_relativeBearing_noHeading_returnsAbsoluteBearing() throws {
        let svc = LocationService()
        svc.simulate(location: tokyoStation)
        // No heading injected — must equal raw bearing(to:).
        let absolute = try XCTUnwrap(svc.bearing(to: sensoji))
        let relative = try XCTUnwrap(svc.relativeBearing(to: sensoji))
        XCTAssertEqual(relative, absolute, accuracy: 0.001)
    }

    // MARK: - Correct subtraction when heading is set

    func test_relativeBearing_subtractsHeading() throws {
        let svc = LocationService()
        svc.simulate(location: tokyoStation)

        // Inject a heading equal to the absolute bearing so the result should be ~0°.
        let absolute = try XCTUnwrap(svc.bearing(to: sensoji))
        svc.simulate(heading: MockHeading(trueHeading: absolute))

        let relative = try XCTUnwrap(svc.relativeBearing(to: sensoji))
        XCTAssertEqual(relative, 0, accuracy: 0.001)
    }

    func test_relativeBearing_exactSubtraction_90minus90_equals0() throws {
        // Place current location directly west of a target at the same latitude so
        // bearing = 90° exactly, then inject heading = 90° → expected result = 0°.
        let svc = LocationService()
        let here = CLLocation(latitude: 35.0, longitude: 139.0)
        let target = CLLocationCoordinate2D(latitude: 35.0, longitude: 139.1) // east
        svc.simulate(location: here)
        svc.simulate(heading: MockHeading(trueHeading: 90))

        let relative = try XCTUnwrap(svc.relativeBearing(to: target))
        // bearing ≈ 90°, heading = 90° → relative ≈ 0°
        // Use normalized comparison to handle floating-point wrap-around (e.g. 359.97° ≅ 0°)
        let diff = min(abs(relative), abs(relative - 360))
        XCTAssertLessThanOrEqual(diff, 1.0)
    }

    // MARK: - Wrap-around past 360°

    func test_relativeBearing_wrapsAroundPast360() throws {
        let svc = LocationService()
        svc.simulate(location: tokyoStation)

        let absolute = try XCTUnwrap(svc.bearing(to: sensoji))
        // Heading is 30° more than the absolute bearing → relative = absolute - (absolute+30) + 360 = 330°
        let headingValue = (absolute + 30).truncatingRemainder(dividingBy: 360)
        svc.simulate(heading: MockHeading(trueHeading: headingValue))

        let relative = try XCTUnwrap(svc.relativeBearing(to: sensoji))
        XCTAssertEqual(relative, 330, accuracy: 0.001)
    }

    func test_relativeBearing_smallBearingLargeHeading_wrapsCorrectly() throws {
        // bearing = 10°, heading = 350° → 10 - 350 + 360 = 20°
        let svc = LocationService()
        // Place current location so bearing to target ≈ 10°.
        // A target slightly north (≈ 0°) and slightly east gives ≈ 10° bearing.
        let here = CLLocation(latitude: 35.0, longitude: 139.0)
        // Small eastward offset with larger northward offset → bearing ≈ 10°
        let target = CLLocationCoordinate2D(latitude: 35.1, longitude: 139.0176)
        svc.simulate(location: here)
        svc.simulate(heading: MockHeading(trueHeading: 350))

        let absolute = try XCTUnwrap(svc.bearing(to: target))
        let relative = try XCTUnwrap(svc.relativeBearing(to: target))
        let expected = (absolute - 350 + 360).truncatingRemainder(dividingBy: 360)
        XCTAssertEqual(relative, expected, accuracy: 0.001)
        // Result must be in [0, 360)
        XCTAssertGreaterThanOrEqual(relative, 0)
        XCTAssertLessThan(relative, 360)
    }

    // MARK: - Invalid heading accuracy is ignored (fallback to absolute)

    func test_relativeBearing_negativeAccuracy_fallsBackToAbsolute() throws {
        let svc = LocationService()
        svc.simulate(location: tokyoStation)
        let absolute = try XCTUnwrap(svc.bearing(to: sensoji))

        // headingAccuracy < 0 means invalid — must be ignored.
        svc.simulate(heading: MockHeading(trueHeading: 45, accuracy: -1))

        let relative = try XCTUnwrap(svc.relativeBearing(to: sensoji))
        XCTAssertEqual(relative, absolute, accuracy: 0.001)
    }

    // MARK: - No location returns nil

    func test_relativeBearing_noLocation_returnsNil() {
        let svc = LocationService()
        XCTAssertNil(svc.relativeBearing(to: sensoji))
    }
}

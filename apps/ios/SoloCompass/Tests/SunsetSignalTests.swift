import XCTest
import CoreLocation
@testable import SoloCompass

/// US-006: SunsetSignal scores viewpoints/parks/rooftop bars highest in the
/// golden window before sunset, fading through blue hour.
final class SunsetSignalTests: XCTestCase {

    // MARK: - Fixtures

    /// Eligible (`.nature`) experience at a fixed coordinate so `SolarEvents`
    /// resolves a deterministic sunset.
    private func experience(
        category: ExperienceCategory = .nature,
        tags: [String] = []
    ) -> Experience {
        let now = Date()
        return Experience(
            id: "sunset_signal_fixture",
            title: "Viewpoint",
            oneLiner: "SunsetSignal fixture",
            whyItMatters: "SunsetSignal test fixture",
            category: category,
            location: ExperienceLocation(coordinates: [102.60, 17.97], cityCode: "vte"),
            bestTimes: [],
            durationMinutes: .init(min: 30, max: 60),
            howTo: [],
            realInconveniences: [],
            soloScore: SoloScore(
                overall: 5,
                breakdown: .init(
                    seatingFriendly: 7, soloPatronRatio: 7, staffPressure: 7,
                    soloPortioning: 7, ambianceFit: 7, safety: 7
                ),
                basedOnCount: 1
            ),
            sources: [InformationSource(type: .user, attribution: "test", verifiedAt: now)],
            confidence: Confidence(
                level: 4,
                lastVerifiedAt: now,
                reason: "Test fixture",
                signals: .init(aiScrapeAgeDays: 1, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .active,
            createdAt: now,
            updatedAt: now,
            userTags: tags
        )
    }

    /// A reference day's sunset for the fixture coordinate, so tests can sample
    /// relative to it without hardcoding clock times.
    private func sunsetInstant() -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents()
        c.year = 2024; c.month = 6; c.day = 21; c.hour = 12
        let day = cal.date(from: c)!
        let coord = CLLocationCoordinate2D(latitude: 17.97, longitude: 102.60)
        return SolarEvents.sunset(at: coord, on: day)!
    }

    private func score(_ exp: Experience, at date: Date) async -> NowSignalContribution {
        await SunsetSignal().score(for: exp, at: date)
    }

    // MARK: - Metadata

    func testKeyAndWeight() {
        XCTAssertEqual(SunsetSignal.key, "sunset")
        XCTAssertEqual(SunsetSignal.weight, 0.25, accuracy: 0.0001)
    }

    // MARK: - Eligibility

    func testNonEligibleCategoryDropsOut() async {
        let c = await score(experience(category: .coffee), at: sunsetInstant())
        XCTAssertEqual(c.weight, 0.0, accuracy: 0.0001)
        XCTAssertEqual(c.value, 0.5, accuracy: 0.0001)
        XCTAssertNil(c.reason)
    }

    func testSunsetFriendlyTagOptsIn() async {
        // A coffee shop tagged sunset_friendly becomes eligible.
        let exp = experience(category: .coffee, tags: ["sunset_friendly"])
        let c = await score(exp, at: sunsetInstant().addingTimeInterval(-45 * 60))
        XCTAssertEqual(c.weight, SunsetSignal.weight, accuracy: 0.0001)
        XCTAssertEqual(c.value, 1.0, accuracy: 0.0001)
    }

    // MARK: - Scoring bands sampled relative to sunset

    /// `offsetMin` < 0 → before sunset, > 0 → after.
    private func sampleValue(offsetMin: Double) async -> Double {
        let date = sunsetInstant().addingTimeInterval(offsetMin * 60)
        return await score(experience(), at: date).value
    }

    func testSixtyMinBeforeIsGolden() async {
        let v = await sampleValue(offsetMin: -60)
        XCTAssertEqual(v, 1.0, accuracy: 0.0001)
    }

    func testThirtyMinBeforeIsGolden() async {
        let v = await sampleValue(offsetMin: -30)
        XCTAssertEqual(v, 1.0, accuracy: 0.0001)
    }

    func testFiveMinBeforeIsDecaying() async {
        let v = await sampleValue(offsetMin: -5)
        // Inside the gaussian decay: below the golden plateau, above the 0.7 floor.
        XCTAssertGreaterThan(v, 0.7)
        XCTAssertLessThan(v, 1.0)
    }

    func testAtSunsetIsNearFloor() async {
        let v = await sampleValue(offsetMin: 0)
        // Decay bottoms out near 0.7 at the moment of sunset.
        XCTAssertEqual(v, 0.715, accuracy: 0.02)
    }

    func testTwentyMinAfterIsBlueHour() async {
        let v = await sampleValue(offsetMin: 20)
        XCTAssertEqual(v, 0.6, accuracy: 0.0001)
    }

    func testSixtyMinAfterIsBaseline() async {
        let v = await sampleValue(offsetMin: 60)
        XCTAssertEqual(v, 0.4, accuracy: 0.0001)
    }

    // MARK: - Reason text

    func testReasonBeforeSunsetIsLocalized() {
        XCTAssertNotNil(SunsetSignal.reason(minutesUntilSunset: 23))
        XCTAssertNotNil(SunsetSignal.reason(minutesUntilSunset: 8))
    }

    func testReasonBlueHourIsLocalized() {
        XCTAssertNotNil(SunsetSignal.reason(minutesUntilSunset: -8))
    }

    func testReasonAfterSunsetIsLocalized() {
        XCTAssertNotNil(SunsetSignal.reason(minutesUntilSunset: -47))
    }

    func testReasonFarBeforeIsNil() {
        XCTAssertNil(SunsetSignal.reason(minutesUntilSunset: 120))
    }
}

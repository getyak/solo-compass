import XCTest
import CoreLocation
@testable import SoloCompass

/// US-005: WeatherSignal downgrades outdoor scores in bad weather and leaves
/// indoor venues untouched.
@MainActor
final class WeatherSignalTests: XCTestCase {

    // MARK: - Mock weather provider

    /// Returns a canned snapshot (or nil to simulate an offline cache miss).
    private struct MockWeather: CurrentWeatherProviding {
        let result: WeatherSnapshot?
        func snapshot(at coord: CLLocationCoordinate2D) async -> WeatherSnapshot? { result }
    }

    private func snapshot(
        condition: WeatherCondition,
        tempC: Double = 27,
        precip: Int = 0,
        windKph: Double = 5
    ) -> WeatherSnapshot {
        WeatherSnapshot(
            tempC: tempC,
            condition: condition,
            precipChancePct: precip,
            windKph: windKph,
            observedAt: Date()
        )
    }

    // MARK: - Fixtures

    private func experience(category: ExperienceCategory, tags: [String] = []) -> Experience {
        let now = Date()
        return Experience(
            id: "weather_signal_fixture",
            title: "Fixture",
            oneLiner: "WeatherSignal fixture",
            whyItMatters: "WeatherSignal test fixture",
            category: category,
            location: ExperienceLocation(coordinates: [98.99, 18.79], cityCode: "cmi"),
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

    private func score(
        _ exp: Experience,
        weather: WeatherSnapshot?
    ) async -> NowSignalContribution {
        let signal = WeatherSignal(weather: MockWeather(result: weather))
        return await signal.score(for: exp, at: Date())
    }

    // MARK: - Metadata

    func testKeyAndWeight() {
        XCTAssertEqual(WeatherSignal.key, "weather")
        XCTAssertEqual(WeatherSignal.weight, 0.15, accuracy: 0.0001)
    }

    // MARK: - Indoor → 1.0 regardless of weather

    func testIndoorCategoriesAlwaysFullStrengthAndNoReason() async {
        // Even in a storm, indoor venues are unaffected.
        let storm = snapshot(condition: .storm, precip: 90, windKph: 40)
        for category in [ExperienceCategory.coffee, .work, .wellness, .culture, .food] {
            let c = await score(experience(category: category), weather: storm)
            XCTAssertEqual(c.value, 1.0, "\(category) should be full strength")
            XCTAssertEqual(c.weight, WeatherSignal.weight, accuracy: 0.0001)
            XCTAssertNil(c.reason, "\(category) should carry no reason")
        }
    }

    func testPlainNightlifeIsIndoor() async {
        // Nightlife without a rooftop tag is indoor → ignores the storm.
        let storm = snapshot(condition: .storm, precip: 90, windKph: 40)
        let c = await score(experience(category: .nightlife), weather: storm)
        XCTAssertEqual(c.value, 1.0)
        XCTAssertNil(c.reason)
    }

    // MARK: - Outdoor scoring ladder

    func testOutdoorClearIsFullStrength() async {
        let c = await score(experience(category: .nature), weather: snapshot(condition: .clear))
        XCTAssertEqual(c.value, 1.0)
        XCTAssertEqual(c.weight, WeatherSignal.weight, accuracy: 0.0001)
        XCTAssertNotNil(c.reason)
    }

    func testOutdoorPartlyCloudyIsFullStrength() async {
        let c = await score(experience(category: .nature), weather: snapshot(condition: .partlyCloudy))
        XCTAssertEqual(c.value, 1.0)
    }

    func testOutdoorCloudyLowPrecipIsNearFull() async {
        let c = await score(
            experience(category: .nature),
            weather: snapshot(condition: .cloudy, precip: 20)
        )
        XCTAssertEqual(c.value, 0.9, accuracy: 0.0001)
    }

    func testOutdoorRainIsHalf() async {
        let c = await score(
            experience(category: .nature),
            weather: snapshot(condition: .rain, precip: 50)
        )
        XCTAssertEqual(c.value, 0.5, accuracy: 0.0001)
    }

    func testOutdoorStormIsZero() async {
        let c = await score(
            experience(category: .nature),
            weather: snapshot(condition: .storm, precip: 90, windKph: 40)
        )
        XCTAssertEqual(c.value, 0.0, accuracy: 0.0001)
    }

    func testHighWindForcesZero() async {
        // Clear condition but dangerous wind → still a hard no.
        let c = await score(
            experience(category: .nature),
            weather: snapshot(condition: .clear, windKph: 35)
        )
        XCTAssertEqual(c.value, 0.0, accuracy: 0.0001)
    }

    func testHighPrecipForcesZero() async {
        // Nominally "rain" but ≥70% precip → storm-grade zero.
        let c = await score(
            experience(category: .nature),
            weather: snapshot(condition: .rain, precip: 80)
        )
        XCTAssertEqual(c.value, 0.0, accuracy: 0.0001)
    }

    // MARK: - Rooftop nightlife is outdoor

    func testRooftopNightlifeIsOutdoorAndDowngrades() async {
        let exp = experience(category: .nightlife, tags: ["rooftop"])
        let c = await score(exp, weather: snapshot(condition: .storm, precip: 90, windKph: 40))
        XCTAssertEqual(c.value, 0.0, accuracy: 0.0001)
        XCTAssertNotNil(c.reason)
    }

    // MARK: - Offline / cache miss → neutral drop-out

    func testOfflineMissReturnsNeutralZeroWeight() async {
        let c = await score(experience(category: .nature), weather: nil)
        XCTAssertEqual(c.value, 0.5, accuracy: 0.0001)
        XCTAssertEqual(c.weight, 0.0, accuracy: 0.0001)
        XCTAssertNil(c.reason)
    }

    // MARK: - Reason text

    func testStormReasonMatchesLadder() async {
        let c = await score(
            experience(category: .nature),
            weather: snapshot(condition: .storm, precip: 90, windKph: 40)
        )
        // Localized storm string (zh: "雷雨预警 · 不建议外出"; en: "Storm warning ...").
        XCTAssertEqual(c.reason, WeatherSignal.reason(for: snapshot(condition: .storm, precip: 90, windKph: 40)))
        XCTAssertFalse(c.reason?.isEmpty ?? true)
    }
}

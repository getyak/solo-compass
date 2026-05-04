import XCTest
import CoreLocation
@testable import SoloCompass

final class SoloCompassTests: XCTestCase {

    // MARK: - Decoding

    func testExperienceDecodingFromBundleSeed() throws {
        // Use the in-code seed which has the same shape as the JSON file.
        let seed = ExperienceService.hardcodedSeed
        XCTAssertGreaterThanOrEqual(seed.count, 5)
        for exp in seed {
            XCTAssertFalse(exp.id.isEmpty, "id required")
            XCTAssertFalse(exp.title.isEmpty, "title required")
            XCTAssertEqual(exp.location.coordinates.count, 2, "coordinates must be [lon,lat]")
        }
    }

    func testExperienceJSONRoundTrip() throws {
        let original = ExperienceService.hardcodedSeed.first!
        let data = try JSONEncoder.iso8601Encoder.encode(original)
        let decoded = try JSONDecoder.iso8601Decoder.decode(Experience.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.category, original.category)
        XCTAssertEqual(decoded.soloScore.overall, original.soloScore.overall, accuracy: 0.001)
    }

    // MARK: - Distance

    func testCLLocationDistanceBetweenChiangMaiPoints() {
        // Old city center → Wat Suan Dok ≈ 2.7km
        let center = CLLocation(latitude: 18.7877, longitude: 98.9938)
        let suanDok = CLLocation(latitude: 18.7892, longitude: 98.9692)
        let distance = center.distance(from: suanDok)
        XCTAssertGreaterThan(distance, 2_000)
        XCTAssertLessThan(distance, 4_000)
    }

    // MARK: - Filtering

    func testFilteringByCategoryAndDistance() {
        let service = ExperienceService()
        let center = CLLocationCoordinate2D(latitude: 18.7877, longitude: 98.9938)
        service.filter(by: .coffee, near: center, maxDistance: 10)
        XCTAssertTrue(service.filteredExperiences.allSatisfy { $0.category == .coffee })
    }

    func testGetExperiencesNearReturnsSortedByDistance() {
        let service = ExperienceService()
        let center = CLLocationCoordinate2D(latitude: 18.7877, longitude: 98.9938)
        let nearby = service.getExperiences(near: center, radiusKm: 50)
        XCTAssertGreaterThan(nearby.count, 0)
        // Sort check: distances should be non-decreasing.
        var lastDistance: CLLocationDistance = 0
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        for exp in nearby {
            let d = here.distance(from: CLLocation(latitude: exp.coordinate.latitude, longitude: exp.coordinate.longitude))
            XCTAssertGreaterThanOrEqual(d, lastDistance - 0.001)
            lastDistance = d
        }
    }

    // MARK: - HealthStatus

    func testHealthHealthyForFreshHighLevel() {
        let confidence = Confidence(
            level: 4,
            lastVerifiedAt: Date(),
            reason: "fresh",
            signals: .init(aiScrapeAgeDays: 1, passiveGpsHits30d: 30, activeReports30d: 10, trustedVerifications: 2)
        )
        XCTAssertEqual(confidence.health, .healthy)
    }

    func testHealthMayBeGoneForStale() {
        let stale = Date().addingTimeInterval(-90 * 86_400) // 90 days ago
        let confidence = Confidence(
            level: 4,
            lastVerifiedAt: stale,
            reason: "stale",
            signals: .init(aiScrapeAgeDays: 90, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
        )
        XCTAssertEqual(confidence.health, .mayBeGone)
    }

    func testHealthQuestionedForLowLevel() {
        let confidence = Confidence(
            level: 1,
            lastVerifiedAt: Date(),
            reason: "low",
            signals: .init(aiScrapeAgeDays: 1, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
        )
        XCTAssertEqual(confidence.health, .questioned)
    }

    // MARK: - Solo Score

    func testSoloScoreRangeValidation() {
        for exp in ExperienceService.hardcodedSeed {
            XCTAssertGreaterThanOrEqual(exp.soloScore.overall, 0)
            XCTAssertLessThanOrEqual(exp.soloScore.overall, 10)
            let b = exp.soloScore.breakdown
            for value in [b.seatingFriendly, b.soloPatronRatio, b.staffPressure, b.soloPortioning, b.ambianceFit, b.safety] {
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThanOrEqual(value, 10)
            }
        }
    }

    func testTimeWindowContainsHour() {
        let day = TimeWindow(startHour: 8, endHour: 17)
        XCTAssertTrue(day.contains(hour: 12))
        XCTAssertFalse(day.contains(hour: 18))

        let night = TimeWindow(startHour: 22, endHour: 4)
        XCTAssertTrue(night.contains(hour: 23))
        XCTAssertTrue(night.contains(hour: 2))
        XCTAssertFalse(night.contains(hour: 12))
    }

    // MARK: - Preferences

    func testUserPreferencesPersistsRoundTrip() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let prefs = UserPreferences(defaults: defaults)
        prefs.maxDistanceKm = 7.5
        prefs.markCompleted("exp_test_1")
        prefs.toggleFavorite("exp_test_2")

        let reloaded = UserPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.maxDistanceKm, 7.5)
        XCTAssertTrue(reloaded.isCompleted("exp_test_1"))
        XCTAssertTrue(reloaded.isFavorited("exp_test_2"))
    }
}

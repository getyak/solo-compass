import XCTest
import CoreLocation
@testable import SoloCompass

/// Unit coverage for `RouteBuilder` — the shared distance/duration estimator
/// and greedy ordering behind both the manual create-route flow and the AI
/// route generator.
final class RouteBuilderTests: XCTestCase {

    // MARK: - Fixtures

    /// Make an experience at a given coordinate ([lon, lat] GeoJSON order).
    private func exp(_ id: String, lon: Double, lat: Double, solo: Double = 8.0) -> Experience {
        let location = ExperienceLocation(coordinates: [lon, lat], cityCode: "vte")
        let breakdown = SoloScore.Breakdown(
            seatingFriendly: 8, soloPatronRatio: 8, staffPressure: 2,
            soloPortioning: 8, ambianceFit: 8, safety: 8
        )
        let confidence = Confidence(
            level: 2, lastVerifiedAt: Date(), reason: "test",
            signals: Confidence.Signals(aiScrapeAgeDays: 1, passiveGpsHits30d: 1, activeReports30d: 1, trustedVerifications: 1)
        )
        return Experience(
            id: id, title: id, oneLiner: "", whyItMatters: "",
            category: .coffee, location: location, bestTimes: [],
            durationMinutes: Experience.DurationRange(min: 30, max: 90),
            howTo: [], realInconveniences: [],
            soloScore: SoloScore(overall: solo, breakdown: breakdown, basedOnCount: 1),
            sources: [], confidence: confidence, nearbyExperienceIds: [],
            stats: Experience.Stats(completionCount: 0, averageRating: 0),
            status: .active, createdAt: Date(), updatedAt: Date()
        )
    }

    // MARK: - Distance

    func testEmptyAndSingleStopHaveZeroDistance() {
        XCTAssertEqual(RouteBuilder.totalDistanceMeters([]), 0)
        XCTAssertEqual(RouteBuilder.totalDistanceMeters([exp("a", lon: 102.6, lat: 17.96)]), 0)
    }

    func testDistanceSumsConsecutiveLegs() {
        let a = exp("a", lon: 102.6000, lat: 17.9600)
        let b = exp("b", lon: 102.6030, lat: 17.9600) // ~318m east
        let c = exp("c", lon: 102.6060, lat: 17.9600) // another ~318m east
        let total = RouteBuilder.totalDistanceMeters([a, b, c])
        let oneLeg = RouteBuilder.totalDistanceMeters([a, b])
        XCTAssertGreaterThan(total, oneLeg)
        XCTAssertGreaterThan(total, 500)
        XCTAssertLessThan(total, 800)
    }

    // MARK: - Duration

    func testDurationIncludesDwellPerStop() {
        let a = exp("a", lon: 102.6000, lat: 17.9600)
        let b = exp("b", lon: 102.6030, lat: 17.9600)
        let duration = RouteBuilder.estimatedDurationMinutes([a, b])
        XCTAssertGreaterThanOrEqual(duration, 2 * RouteBuilder.dwellMinutesPerStop)
    }

    func testSingleStopStillHasDwellTime() {
        let a = exp("a", lon: 102.6, lat: 17.96)
        XCTAssertEqual(RouteBuilder.estimatedDurationMinutes([a]), RouteBuilder.dwellMinutesPerStop)
    }

    // MARK: - Nearest-neighbour ordering

    func testNearestNeighbourOrdersByProximityFromOrigin() {
        let a = exp("a", lon: 102.6000, lat: 17.9600)
        let b = exp("b", lon: 102.6030, lat: 17.9600)
        let c = exp("c", lon: 102.6090, lat: 17.9600)
        let origin = CLLocationCoordinate2D(latitude: 17.9600, longitude: 102.5990)
        let ordered = RouteBuilder.nearestNeighbourOrder([c, b, a], from: origin)
        XCTAssertEqual(ordered.map(\.id), ["a", "b", "c"], "Greedy walk should visit nearest-first from the origin")
    }

    func testNearestNeighbourEmptyIsEmpty() {
        XCTAssertTrue(RouteBuilder.nearestNeighbourOrder([], from: nil).isEmpty)
    }

    // MARK: - makeRoute

    func testMakeRouteDerivesDistanceDurationAndIds() {
        let a = exp("a", lon: 102.6000, lat: 17.9600)
        let b = exp("b", lon: 102.6030, lat: 17.9600)
        let route = RouteBuilder.makeRoute(
            id: RouteId(rawValue: "r1"),
            title: "Test Walk",
            summary: "s",
            orderedExperiences: [a, b],
            cityCode: "VTE",
            source: .userCreated
        )
        XCTAssertEqual(route.experienceIds, ["a", "b"])
        XCTAssertEqual(route.distanceMeters, RouteBuilder.totalDistanceMeters([a, b]))
        XCTAssertEqual(route.estimatedDuration, RouteBuilder.estimatedDurationMinutes([a, b]))
        XCTAssertEqual(route.source, .userCreated)
        XCTAssertEqual(route.verification.status, .proposed)
    }
}

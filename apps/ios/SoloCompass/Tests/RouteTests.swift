import XCTest
@testable import SoloCompass

final class RouteTests: XCTestCase {

    // MARK: - RouteVerification defaults

    func testRouteVerificationDefaults() {
        let verification = RouteVerification()
        XCTAssertEqual(verification.status, .proposed)
        XCTAssertEqual(verification.walkedByCount, 0)
        XCTAssertTrue(verification.walkedBy.isEmpty)
    }

    // MARK: - Construction

    func testRouteConstructionUsesDefaultVerification() {
        let route = makeRoute()
        XCTAssertEqual(route.verification.status, .proposed)
        XCTAssertEqual(route.verification.walkedByCount, 0)
        XCTAssertTrue(route.verification.walkedBy.isEmpty)
        XCTAssertFalse(route.bestNow)
        XCTAssertNil(route.authorId)
        XCTAssertNil(route.bestStartHour)
        XCTAssertNil(route.companion)
        XCTAssertTrue(route.tags.isEmpty)
    }

    func testRouteExperienceIdsPreserveOrder() {
        let ids = ["exp-alpha", "exp-beta", "exp-gamma", "exp-delta"]
        let route = makeRoute(experienceIds: ids)
        XCTAssertEqual(route.experienceIds, ids)
        let reversed = makeRoute(experienceIds: Array(ids.reversed()))
        XCTAssertEqual(reversed.experienceIds, Array(ids.reversed()))
        XCTAssertNotEqual(route.experienceIds, reversed.experienceIds)
    }

    // MARK: - Codable round trip

    func testRouteJSONRoundTrip() throws {
        let original = makeRoute(
            experienceIds: ["exp-1", "exp-2", "exp-3"],
            tags: ["scenic", "morning"],
            authorId: "user-42",
            bestStartHour: 9.5,
            bestNow: true,
            verification: RouteVerification(
                status: .verified,
                walkedByCount: 3,
                walkedBy: ["user-1", "user-2", "user-3"]
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Route.self, from: data)

        XCTAssertEqual(decoded.id.rawValue, original.id.rawValue)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.summary, original.summary)
        XCTAssertEqual(decoded.experienceIds, original.experienceIds)
        XCTAssertEqual(decoded.cityCode, original.cityCode)
        XCTAssertEqual(decoded.region, original.region)
        XCTAssertEqual(decoded.estimatedDuration, original.estimatedDuration)
        XCTAssertEqual(decoded.distanceMeters, original.distanceMeters)
        XCTAssertEqual(decoded.pace, original.pace)
        XCTAssertEqual(decoded.tags, original.tags)
        XCTAssertEqual(decoded.source, original.source)
        XCTAssertEqual(decoded.authorId, original.authorId)
        XCTAssertEqual(decoded.bestStartHour, original.bestStartHour)
        XCTAssertEqual(decoded.bestNow, original.bestNow)
        XCTAssertEqual(decoded.verification.status, original.verification.status)
        XCTAssertEqual(decoded.verification.walkedByCount, original.verification.walkedByCount)
        XCTAssertEqual(decoded.verification.walkedBy, original.verification.walkedBy)
    }

    // MARK: - Enum codability

    func testPaceCodability() throws {
        try assertEnumRoundTrips(Pace.self)
    }

    func testRouteSourceCodability() throws {
        try assertEnumRoundTrips(RouteSource.self)
    }

    func testVerificationStatusCodability() throws {
        try assertEnumRoundTrips(VerificationStatus.self)
    }

    // MARK: - Helpers

    private func makeRoute(
        id: String = "route-test",
        experienceIds: [String] = ["exp-1", "exp-2"],
        tags: [String] = [],
        source: RouteSource = .editorial,
        authorId: String? = nil,
        bestStartHour: Double? = nil,
        bestNow: Bool = false,
        verification: RouteVerification = RouteVerification()
    ) -> Route {
        Route(
            id: RouteId(rawValue: id),
            title: "Test Route",
            summary: "A test summary",
            experienceIds: experienceIds,
            cityCode: "tyo",
            region: "Shibuya",
            estimatedDuration: 90,
            distanceMeters: 2400,
            pace: .standard,
            tags: tags,
            source: source,
            authorId: authorId,
            bestStartHour: bestStartHour,
            bestNow: bestNow,
            verification: verification
        )
    }

    private func assertEnumRoundTrips<T: Codable & Equatable & CaseIterable>(
        _ type: T.Type,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        for value in T.allCases {
            let data = try JSONEncoder().encode([value])
            let decoded = try JSONDecoder().decode([T].self, from: data)
            XCTAssertEqual(decoded.first, value, file: file, line: line)
        }
    }
}

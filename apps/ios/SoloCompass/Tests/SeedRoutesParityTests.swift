import XCTest
@testable import SoloCompass

/// Verifies every experienceId referenced by `seed_routes.json` resolves
/// in `seed_experiences.json`. Guards against silent drift when either
/// seed file is hand-edited.
final class SeedRoutesParityTests: XCTestCase {

    func testEverySeedRouteExperienceIdResolvesInSeedExperiences() throws {
        let routes = try loadRoutes()
        let experiences = try loadExperiences()
        let knownIds = Set(experiences.map(\.id))

        XCTAssertEqual(routes.count, 5, "seed_routes.json should contain 4 Vientiane + 1 Chiang Mai route")

        var missing: [(routeId: String, experienceId: String)] = []
        for route in routes {
            XCTAssertTrue(
                ["VTE", "cmi"].contains(route.cityCode),
                "Seed route cityCode must be one of the curated cities (got \(route.cityCode))"
            )
            XCTAssertFalse(
                route.experienceIds.isEmpty,
                "Route \(route.id.rawValue) must reference at least one experience"
            )
            for expId in route.experienceIds where !knownIds.contains(expId) {
                missing.append((route.id.rawValue, expId))
            }
        }

        XCTAssertTrue(
            missing.isEmpty,
            "seed_routes.json references experienceIds not present in seed_experiences.json: " +
                missing.map { "\($0.routeId)→\($0.experienceId)" }.joined(separator: ", ")
        )
    }

    func testSeedRoutesCoverFourExpectedIds() throws {
        let routes = try loadRoutes()
        let ids = Set(routes.map { $0.id.rawValue })
        XCTAssertEqual(
            ids,
            Set([
                "mekong-sunset",
                "slow-coffee-day",
                "morning-ritual",
                "vientiane-monuments",
                "nimman-slow-morning"
            ])
        )
    }

    /// P1: each seed route carries the expected companion fixture shape.
    func testSeedRoutesCompanionFixtures() throws {
        let routes = try loadRoutes()
        let byId = Dictionary(uniqueKeysWithValues: routes.map { ($0.id.rawValue, $0) })

        // mekong-sunset: open, 2 confirmed, 2 pending
        let mekong = try XCTUnwrap(byId["mekong-sunset"]?.companion, "mekong-sunset must have companion")
        XCTAssertEqual(mekong.status, .open)
        XCTAssertEqual(mekong.confirmedMembers.count, 2)
        XCTAssertEqual(mekong.joinRequests.filter { $0.status == .pending }.count, 2)
        XCTAssertEqual(mekong.maxMembers, 4)

        // slow-coffee-day: forming, 3 confirmed
        let coffee = try XCTUnwrap(byId["slow-coffee-day"]?.companion, "slow-coffee-day must have companion")
        XCTAssertEqual(coffee.status, .forming)
        XCTAssertEqual(coffee.confirmedMembers.count, 3)
        XCTAssertEqual(coffee.maxMembers, 4)

        // morning-ritual: no companion (nil)
        XCTAssertNil(byId["morning-ritual"]?.companion, "morning-ritual must have companion=null")

        // vientiane-monuments: completed, 4/4 confirmed
        let monuments = try XCTUnwrap(byId["vientiane-monuments"]?.companion, "vientiane-monuments must have companion")
        XCTAssertEqual(monuments.status, .completed)
        XCTAssertEqual(monuments.confirmedMembers.count, 4)
        XCTAssertEqual(monuments.maxMembers, 4)
    }

    // MARK: - Helpers

    private func loadRoutes() throws -> [Route] {
        let data = try Data(contentsOf: try url(for: "seed_routes"))
        return try JSONDecoder().decode([Route].self, from: data)
    }

    private func loadExperiences() throws -> [Experience] {
        let data = try Data(contentsOf: try url(for: "seed_experiences"))
        return try JSONDecoder.iso8601Decoder.decode([Experience].self, from: data)
    }

    /// Both seed files are wired into the test target's resources via
    /// `apps/ios/project.yml` so `Bundle(for:)` can locate them. Fall back to
    /// `Bundle.main` in case the test ever runs under a host app.
    private func url(for name: String) throws -> URL {
        let testBundle = Bundle(for: type(of: self))
        if let url = testBundle.url(forResource: name, withExtension: "json") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "json") {
            return url
        }
        throw NSError(
            domain: "SeedRoutesParityTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing bundled resource \(name).json"]
        )
    }
}

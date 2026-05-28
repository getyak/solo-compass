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

        XCTAssertEqual(routes.count, 4, "seed_routes.json should contain exactly 4 Vientiane routes")

        var missing: [(routeId: String, experienceId: String)] = []
        for route in routes {
            XCTAssertEqual(route.cityCode, "VTE", "All seed routes are Vientiane (cityCode=VTE)")
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
            Set(["mekong-sunset", "slow-coffee-day", "morning-ritual", "vientiane-monuments"])
        )
    }

    func testSeedRoutesCompanionFieldIsNilInP0() throws {
        let routes = try loadRoutes()
        for route in routes {
            XCTAssertNil(
                route.companion,
                "Route \(route.id.rawValue) must have companion=null in P0; status populated in P1"
            )
        }
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

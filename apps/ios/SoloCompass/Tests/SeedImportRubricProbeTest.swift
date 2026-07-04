import XCTest
import SwiftData
@testable import SoloCompass

/// Ground-truth probe for the rubric e2e harness:
/// verify the bundled seed_experiences.json parses cleanly and yields the
/// expected per-city coverage. When simctl screenshots report "Nearby 0" the
/// first check is: did the bundle even decode? This test answers that with a
/// crash-free, decoder-strict pass.
@MainActor
final class SeedImportRubricProbeTest: XCTestCase {

    private func makeRepo() -> ExperienceRepository {
        let container = SoloCompassModelContainer.makeInMemory()
        return ExperienceRepository(context: ModelContext(container))
    }

    func testBundledSeedLoadsWithExpectedCityCoverage() throws {
        let repo = makeRepo()
        let added = repo.importSeedIfNeeded()

        XCTAssertGreaterThanOrEqual(added, 34, "expected ≥34 bundled rows (10 legacy + 24 rubric fixture)")

        let all = repo.allExperiences()
        let byCity = Dictionary(grouping: all, by: { $0.location.cityCode })

        // Cities the user-story rubric fixture drives.
        XCTAssertGreaterThanOrEqual(byCity["cn-深圳市"]?.count ?? 0, 4, "SZX seed coverage — s01/s02/s07")
        XCTAssertGreaterThanOrEqual(byCity["nyc"]?.count ?? 0, 4, "NYC seed coverage — s03")
        XCTAssertGreaterThanOrEqual(byCity["tyo"]?.count ?? 0, 4, "Tokyo seed coverage — s04/s09")
        XCTAssertGreaterThanOrEqual(byCity["san-francisco"]?.count ?? 0, 4, "SF seed coverage — s05")
        XCTAssertGreaterThanOrEqual(byCity["sgn"]?.count ?? 0, 4, "SGN seed coverage — s06/s10")
        XCTAssertGreaterThanOrEqual(byCity["lis"]?.count ?? 0, 4, "Lisbon seed coverage — s08")
    }

    /// Sanity: `sources.type` must fit the allowed enum. A single unknown value
    /// (e.g. "osm") silently blanks the whole `sources` field via
    /// `decodeOrLog`, and rows lose their attribution chain.
    func testAllSeedSourcesUseKnownEnumTypes() throws {
        let repo = makeRepo()
        _ = repo.importSeedIfNeeded()

        let all = repo.allExperiences()
        let allowed: Set<InformationSource.SourceType> = [
            .wikivoyage, .wikipedia, .reddit, .blog, .youtube, .user, .fieldVisit, .amap
        ]
        for exp in all {
            for src in exp.sources {
                XCTAssertTrue(
                    allowed.contains(src.type),
                    "unknown source type '\(src.type.rawValue)' on \(exp.id) — check seed_experiences.json"
                )
            }
        }
    }
}

import XCTest
@testable import SoloCompass

/// Tests for the P3.2 #320 Solo Brag card template system.
///
/// The 5 base card faces are shipped as programmatic stand-ins (SwiftUI
/// Canvas + LinearGradient) so end-users get a designed background before
/// real illustrator PNGs land. Once art delivers, PNG assets sit under
/// `Assets.xcassets/BragCards/<rawValue>.imageset` — so any rename after
/// ship BOTH breaks the assets AND invalidates users' cached card faces.
final class BragCardTemplateTests: XCTestCase {

    // MARK: - Raw value stability contract (matches asset filenames)

    func testTemplateRawValuesLockedToAssetFilenames() {
        XCTAssertEqual(BragCardTemplate.sun.rawValue,        "templateA_sun")
        XCTAssertEqual(BragCardTemplate.lateWindow.rawValue, "templateB_lateWindow")
        XCTAssertEqual(BragCardTemplate.rain.rawValue,       "templateC_rain")
        XCTAssertEqual(BragCardTemplate.dusk.rawValue,       "templateD_dusk")
        XCTAssertEqual(BragCardTemplate.still.rawValue,      "templateE_still")
    }

    func testAllCasesHasExactlyFiveTemplates() {
        // Design brief called for exactly 5 base card faces; adding a 6th
        // requires updating the asset brief + external illustrator scope.
        XCTAssertEqual(BragCardTemplate.allCases.count, 5)
    }

    func testEveryTemplateHasNonEmptyDisplayName() {
        for t in BragCardTemplate.allCases {
            XCTAssertFalse(t.displayName.isEmpty, "\(t) missing display name")
        }
    }

    // MARK: - Deterministic seeded selection

    func testDeterministicSeedIsStable() {
        let picks = (0..<3).map { _ in BragCardTemplate.deterministic(for: "cmi-6day") }
        XCTAssertEqual(Set(picks).count, 1, "same seed must map to same template")
    }

    func testDeterministicSeedsDistributeAcrossTemplates() {
        // Ten distinct seeds should not all collapse to one template — a
        // pathological hash would let a single face dominate.
        let seeds = (0..<20).map { "seed-\($0)" }
        let picks = Set(seeds.map { BragCardTemplate.deterministic(for: $0) })
        XCTAssertGreaterThanOrEqual(picks.count, 3,
                                    "hash must spread across at least 3 templates")
    }

    func testDeterministicPickAlwaysReturnsValidCase() {
        for seed in ["", " ", "x", "!!!", "长文本 seed 中文"] {
            let template = BragCardTemplate.deterministic(for: seed)
            XCTAssertTrue(BragCardTemplate.allCases.contains(template))
        }
    }

    // MARK: - Codable round-trip (persistence contract)

    func testCodableRoundTripPreservesRawValue() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for original in BragCardTemplate.allCases {
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(BragCardTemplate.self, from: data)
            XCTAssertEqual(decoded, original)
        }
    }
}

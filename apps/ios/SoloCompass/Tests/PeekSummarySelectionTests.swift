import XCTest
import CoreLocation
@testable import SoloCompass

/// Unit coverage for `PeekPickResolver` — the pure selector that picks the single
/// experience surfaced in the BottomInfoSheet's peek summary card.
///
/// The selection rule is the load-bearing part of the "此刻最值得去" peek card, so
/// it lives in a side-effect-free resolver that can be exercised without a
/// SwiftUI graph or a live MapViewModel. These tests pin every branch:
///  - empty visible set → nil
///  - first visible smart pick wins
///  - smart pick not visible → nearest fallback
///  - multiple smart picks → the first one
///  - localization keys resolve in both shipped locales
@MainActor
final class PeekSummarySelectionTests: XCTestCase {

    /// Minimal experience fixture at the given coordinate. Mirrors the
    /// `makeExperience` pattern used by FavoriteFilterTests / ColdStartTests.
    private func makeExperience(id: String, lon: Double, lat: Double) -> Experience {
        let now = Date()
        return Experience(
            id: id,
            title: "Peek Fixture \(id)",
            oneLiner: "Fixture \(id)",
            whyItMatters: "Peek summary fixture",
            category: .food,
            location: ExperienceLocation(coordinates: [lon, lat], cityCode: "cmi"),
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
                level: 3,
                lastVerifiedAt: now,
                reason: "Test fixture",
                signals: .init(aiScrapeAgeDays: 1, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .active,
            createdAt: now,
            updatedAt: now
        )
    }

    /// Chiang Mai reference coordinate used as the distance origin.
    private let cmiCenter = CLLocationCoordinate2D(latitude: 18.7877, longitude: 98.9938)

    // MARK: - Empty

    func testEmptyVisibleSetResolvesToNil() {
        let result = PeekPickResolver.resolve(
            experiences: [],
            smartPickIds: ["anything"],
            referenceCoordinate: cmiCenter
        )
        XCTAssertNil(result, "no visible experiences → no peek pick")
    }

    // MARK: - Smart pick precedence

    func testFirstSmartPickWinsOverNearest() {
        // `far` is the AI's pick but is geographically the farthest — it must
        // still be chosen because smart picks outrank distance.
        let near = makeExperience(id: "near", lon: 98.9939, lat: 18.7878) // ~15m
        let far = makeExperience(id: "far", lon: 99.5000, lat: 18.7877)   // ~50km+
        let result = PeekPickResolver.resolve(
            experiences: [near, far],
            smartPickIds: ["far"],
            referenceCoordinate: cmiCenter
        )
        XCTAssertEqual(result?.id, "far", "the visible smart pick wins regardless of distance")
        XCTAssertTrue(
            PeekPickResolver.isSmartPick(resolved: result, smartPickIds: ["far"]),
            "resolved smart pick is flagged as smart"
        )
    }

    func testMultipleSmartPicksTakesFirst() {
        let a = makeExperience(id: "a", lon: 98.9940, lat: 18.7880)
        let b = makeExperience(id: "b", lon: 98.9942, lat: 18.7882)
        let result = PeekPickResolver.resolve(
            experiences: [a, b],
            smartPickIds: ["b", "a"], // b is first in the ranked list
            referenceCoordinate: cmiCenter
        )
        XCTAssertEqual(result?.id, "b", "the first smart-pick id in the ranked list wins")
    }

    // MARK: - Nearest fallback

    func testSmartPickNotVisibleFallsBackToNearest() {
        let near = makeExperience(id: "near", lon: 98.9939, lat: 18.7878) // ~15m
        let far = makeExperience(id: "far", lon: 99.2000, lat: 18.9000)   // far away
        // The smart pick id is not present in the visible set, so the resolver
        // must fall back to the nearest visible experience.
        let result = PeekPickResolver.resolve(
            experiences: [far, near],
            smartPickIds: ["ghost-id-not-visible"],
            referenceCoordinate: cmiCenter
        )
        XCTAssertEqual(result?.id, "near", "with no visible smart pick, the nearest experience wins")
        XCTAssertFalse(
            PeekPickResolver.isSmartPick(resolved: result, smartPickIds: ["ghost-id-not-visible"]),
            "a nearest-fallback pick is not flagged as a smart pick"
        )
    }

    func testNoSmartPicksFallsBackToNearest() {
        let near = makeExperience(id: "near", lon: 98.9939, lat: 18.7878)
        let far = makeExperience(id: "far", lon: 99.2000, lat: 18.9000)
        let result = PeekPickResolver.resolve(
            experiences: [far, near],
            smartPickIds: [],
            referenceCoordinate: cmiCenter
        )
        XCTAssertEqual(result?.id, "near", "empty smart-pick list → nearest experience")
    }

    func testNilReferenceFallsBackToFirstExperience() {
        let a = makeExperience(id: "a", lon: 98.99, lat: 18.78)
        let b = makeExperience(id: "b", lon: 98.98, lat: 18.77)
        let result = PeekPickResolver.resolve(
            experiences: [a, b],
            smartPickIds: [],
            referenceCoordinate: nil
        )
        XCTAssertEqual(result?.id, "a", "with no reference coordinate, the first experience is the fallback")
    }

    // MARK: - Shuffle rotation ("换一个")

    func testExcludingShuffledSmartPickDealsNextRankedPick() {
        let a = makeExperience(id: "a", lon: 98.9940, lat: 18.7880)
        let b = makeExperience(id: "b", lon: 98.9942, lat: 18.7882)
        // "b" was shuffled away — the next smart pick in rank order deals.
        let result = PeekPickResolver.resolve(
            experiences: [a, b],
            smartPickIds: ["b", "a"],
            referenceCoordinate: cmiCenter,
            excluding: ["b"]
        )
        XCTAssertEqual(result?.id, "a", "shuffling away the top smart pick deals the next ranked one")
    }

    func testExcludingAllSmartPicksFallsBackToWarmStart() {
        let smart = makeExperience(id: "smart", lon: 98.9940, lat: 18.7880)
        let plain = makeExperience(id: "plain", lon: 98.9939, lat: 18.7878)
        let result = PeekPickResolver.resolve(
            experiences: [smart, plain],
            smartPickIds: ["smart"],
            referenceCoordinate: cmiCenter,
            excluding: ["smart"]
        )
        XCTAssertEqual(result?.id, "plain", "with every smart pick shuffled away, the warm-start fallback deals")
    }

    func testExclusionCoveringEverythingWrapsToFullSet() {
        let a = makeExperience(id: "a", lon: 98.9940, lat: 18.7880)
        let b = makeExperience(id: "b", lon: 98.9942, lat: 18.7882)
        // The rotation has cycled through everything visible — the resolver
        // wraps to the full set so "换一个" never comes back empty-handed.
        let result = PeekPickResolver.resolve(
            experiences: [a, b],
            smartPickIds: ["b", "a"],
            referenceCoordinate: cmiCenter,
            excluding: ["a", "b"]
        )
        XCTAssertEqual(result?.id, "b", "a fully-covered exclusion wraps the rotation back to the top pick")
    }

    // MARK: - Localization key presence (both shipped locales)

    /// The peek-card keys this feature introduces. Both shipped `.lproj` tables
    /// must define every one (the QA brief checks bilingual coverage).
    private static let peekKeys = [
        "peek.pick.header", "peek.empty.hint", "sheet.handle.hint",
        // North-star card rows + actions (PRD solo-city-os-v2 §5.1).
        "peek.now.goodTime", "peek.confidence.basedOn", "peek.confidence.basedOn.one",
        "peek.confidence.aiEstimate", "peek.action.go", "peek.action.shuffle"
    ]

    func testPeekLocalizationKeysResolveInEnglish() throws {
        let defined = try definedKeys(localeID: "en")
        for key in Self.peekKeys {
            XCTAssertTrue(defined.contains(key), "en/Localizable.strings is missing \(key)")
        }
    }

    func testPeekLocalizationKeysResolveInSimplifiedChinese() throws {
        let defined = try definedKeys(localeID: "zh-Hans")
        for key in Self.peekKeys {
            XCTAssertTrue(defined.contains(key), "zh-Hans/Localizable.strings is missing \(key)")
        }
    }

    /// Parse the keys defined in a locale's `Localizable.strings`, read straight
    /// from the source tree via `#filePath` (the iOS test bundle runs in the
    /// Simulator sandbox where the source tree may be absent, so `XCTSkip` when it
    /// isn't reachable — mirrors `ZhHansPunctuationTest`).
    private func definedKeys(localeID: String, file: StaticString = #filePath) throws -> Set<String> {
        let url = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // SoloCompass/
            .appendingPathComponent("Resources/\(localeID).lproj/Localizable.strings")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Source tree not reachable in this run: \(url.path)")
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        var keys = Set<String>()
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match `"key" = "value";` — capture the first quoted token as the key.
            guard trimmed.hasPrefix("\"") else { continue }
            let afterFirstQuote = trimmed.dropFirst()
            guard let endQuote = afterFirstQuote.firstIndex(of: "\"") else { continue }
            keys.insert(String(afterFirstQuote[..<endQuote]))
        }
        return keys
    }
}

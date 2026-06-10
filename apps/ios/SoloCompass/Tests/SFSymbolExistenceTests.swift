import XCTest
import UIKit
@testable import SoloCompass

/// Regression for the blank navigation button on the Experience detail action
/// bar. `arrow.triangle.turn.up.right.diagonal` is NOT a real SF Symbol, so
/// `Image(systemName:)` rendered an empty circle with no error — the build
/// stayed green and the icon silently vanished.
///
/// SwiftUI/UIKit never validate `systemName` at compile time, so a typo'd or
/// renamed symbol only shows up as a blank glyph at runtime. This test scans
/// view source files for every `Image(systemName: "…")` and `systemImage: "…"`
/// literal and asserts each resolves to a real `UIImage(systemName:)`, catching
/// ghost symbols before they ship.
@MainActor
final class SFSymbolExistenceTests: XCTestCase {

    /// View files to scan. Start with the detail view (where the bug lived);
    /// add more as needed — the scanner is generic.
    private let relativeViewPaths = [
        "Views/Experience/ExperienceDetailView.swift",
        "Views/Experience/TravelerNotesSection.swift",
        "Views/Experience/ExperienceCardView.swift",
        "Views/Map/CompassMapView.swift",
        "Views/Map/BottomInfoSheet.swift",
        "Views/Experience/LocationCard.swift",
    ]

    func testNoGhostSFSymbolsInScannedViews() throws {
        let sourceRoot = Self.sourceRoot()
        var missing: [String] = []
        var scannedFiles = 0
        var scannedSymbols = 0

        for rel in relativeViewPaths {
            let url = sourceRoot.appendingPathComponent(rel)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                // Don't silently pass if the path drifts — fail loudly.
                XCTFail("Could not read source file for scanning: \(rel)")
                continue
            }
            scannedFiles += 1
            for name in Self.extractSymbolNames(from: text) {
                scannedSymbols += 1
                if UIImage(systemName: name) == nil {
                    missing.append("\(rel): \"\(name)\"")
                }
            }
        }

        XCTAssertEqual(scannedFiles, relativeViewPaths.count, "All listed view files must be scannable")
        XCTAssertGreaterThan(scannedSymbols, 0, "Scanner must have found at least one SF Symbol literal")
        XCTAssertTrue(
            missing.isEmpty,
            "Found SF Symbol names that don't resolve to a real UIImage "
                + "(blank-glyph bug). Fix or rename:\n" + missing.joined(separator: "\n")
        )
    }

    /// Spot-check: the exact symbol we corrected must exist, and the ghost name
    /// must stay gone. Cheap guard against a careless revert.
    func testNavigationArrowSymbolIsReal() {
        XCTAssertNotNil(
            UIImage(systemName: "arrow.triangle.turn.up.right.diamond.fill"),
            "The detail action-bar navigation icon must be a real SF Symbol"
        )
        XCTAssertNil(
            UIImage(systemName: "arrow.triangle.turn.up.right.diagonal"),
            "The ghost symbol must not silently come back as a real one"
        )
    }

    // MARK: - Helpers

    /// Pull every `Image(systemName: "…")` and `systemImage: "…"` literal name.
    /// Only matches static string literals (the case that fails silently);
    /// interpolated/dynamic names are out of scope.
    static func extractSymbolNames(from source: String) -> [String] {
        let patterns = [
            #"Image\(systemName:\s*"([^"]+)""#,
            #"systemImage:\s*"([^"]+)""#,
        ]
        var names: [String] = []
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(source.startIndex..., in: source)
            re.enumerateMatches(in: source, range: range) { match, _, _ in
                guard let m = match, m.numberOfRanges >= 2,
                      let r = Range(m.range(at: 1), in: source) else { return }
                names.append(String(source[r]))
            }
        }
        return names
    }

    /// `apps/ios/SoloCompass/` — derived from this test file's compile-time path
    /// (`…/SoloCompass/Tests/SFSymbolExistenceTests.swift`).
    private static func sourceRoot(file: StaticString = #filePath) -> URL {
        // .../SoloCompass/Tests/SFSymbolExistenceTests.swift
        //   → drop file (Tests/…) and the Tests dir → .../SoloCompass/
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // SoloCompass/
    }
}

import XCTest

/// US-055: Public-API documentation ratchet.
///
/// Every top-level `public class/struct/enum/protocol/func/actor` declared in
/// `Models/`, `Services/`, and `ViewModels/` must carry at least a single-line
/// doc comment (`///` or a `/** … */` block) so API consumers can understand a
/// symbol's purpose without reading its body. `Views/` is intentionally excluded
/// — SwiftUI views document themselves via `#Preview`.
///
/// Like `NoProductionPrintTests` / `LocalizationCoverageTest`, the iOS test
/// bundle runs in the Simulator sandbox where the source tree may be absent, so
/// the audit is re-implemented in pure Swift over the source resolved from
/// `#filePath` and `XCTSkip`s when that tree isn't reachable.
final class PublicAPIDocCommentTests: XCTestCase {

    /// Directories whose public API surface is audited (relative to the app root).
    private static let auditedDirectories = ["Models", "Services", "ViewModels"]

    /// Absolute path to apps/ios/SoloCompass derived from this file's location:
    /// .../SoloCompass/Tests/PublicAPIDocCommentTests.swift → .../SoloCompass
    private func appRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // SoloCompass/
    }

    private func swiftFiles(under dir: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator
        where url.pathExtension == "swift" && !url.path.contains("/Tests/") {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    /// Matches a `public` declaration of a documentable symbol, tolerating the
    /// modifiers that can sit between `public` and the keyword
    /// (`final`, `static`, `indirect`, `@unchecked`, `convenience`, `class`).
    /// Mirrors the regex used by the offline detector for this story.
    private static let declRegex = try! NSRegularExpression(
        pattern: #"^\s*public\s+(?:final\s+|indirect\s+|@unchecked\s+|static\s+|class\s+|convenience\s+)*(?:class|struct|enum|protocol|func|actor)\b"#
    )

    /// Returns the 1-based line numbers of undocumented public declarations in `text`.
    /// A declaration is "documented" when the nearest non-blank, non-attribute line
    /// above it begins a doc comment (`///`, `/**`) or is part of one (`*`, `*/`).
    private func undocumentedPublicDeclarations(in text: String) -> [Int] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var offenders: [Int] = []

        for (idx, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            guard PublicAPIDocCommentTests.declRegex.firstMatch(in: line, range: range) != nil else {
                continue
            }

            // Walk upward, skipping blank lines and attribute-only lines (@…),
            // to find the nearest meaningful line. It documents this symbol if it
            // is (or closes) a doc comment.
            var j = idx - 1
            var documented = false
            while j >= 0 {
                let s = lines[j].trimmingCharacters(in: .whitespaces)
                if s.isEmpty { j -= 1; continue }
                if s.hasPrefix("@") { j -= 1; continue }   // attribute on its own line
                if s.hasPrefix("///") || s.hasPrefix("/**") || s.hasPrefix("*") || s.hasSuffix("*/") {
                    documented = true
                }
                break
            }

            if !documented {
                offenders.append(idx + 1)
            }
        }
        return offenders
    }

    // MARK: - Tests

    /// Spot-check on a file that was documented as part of US-055
    /// (`Models/Route.swift`) so the audit's intent is exercised even on hosts
    /// where the full tree walk is skipped.
    func testKnownDocumentedFileHasNoUndocumentedPublicAPI() throws {
        let url = appRoot().appendingPathComponent("Models/Route.swift")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("Route.swift not reachable from test host — sandboxed run")
        }
        let offenders = undocumentedPublicDeclarations(in: text)
        XCTAssertEqual(
            offenders, [],
            "Route.swift has public symbols lacking a /// doc comment. "
                + "Offending line numbers: \(offenders)"
        )
    }

    /// Full sweep: no top-level public symbol in `Models/`, `Services/`, or
    /// `ViewModels/` may lack a doc comment. This is the enforceable ratchet for
    /// US-055 — a new undocumented public API fails this test.
    func testAllPublicAPIsHaveDocComments() throws {
        let root = appRoot()
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("SoloCompass source not reachable from test host — sandboxed run")
        }

        var offenders: [String] = []
        for dirName in PublicAPIDocCommentTests.auditedDirectories {
            let dir = root.appendingPathComponent(dirName)
            guard FileManager.default.fileExists(atPath: dir.path) else { continue }
            for fileURL in swiftFiles(under: dir) {
                guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                for lineNo in undocumentedPublicDeclarations(in: text) {
                    offenders.append("\(dirName)/\(fileURL.lastPathComponent):\(lineNo)")
                }
            }
        }

        XCTAssertEqual(
            offenders.count, 0,
            "Public symbols missing a /// doc comment (US-055). Add a one- or "
                + "two-line doc comment explaining the symbol's purpose. Offenders:\n"
                + offenders.joined(separator: "\n")
        )
    }
}

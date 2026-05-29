import XCTest

/// US-053: Comment-only TODO/FIXME ratchet.
///
/// After the US-053 sweep the iOS Swift sources carried *zero* unreferenced
/// `TODO`/`FIXME` comments. This test keeps that state honest: any TODO or
/// FIXME that lands in production code from now on must reference a tracked
/// GitHub issue in the form `TODO(#NNN):` / `FIXME(#NNN):`, so a stale,
/// untracked marker fails a unit test rather than silently rotting.
///
/// Like `NoProductionPrintTests` / `LocalizationCoverageTest`, the iOS test
/// bundle runs in the Simulator sandbox where the source tree may be absent,
/// so the audit is re-implemented in pure Swift over the source resolved from
/// `#filePath` and `XCTSkip`s when that tree isn't reachable.
///
/// Two classes of marker are intentionally NOT counted:
///   1. Anything under a `Tests/` directory (this file itself contains the
///      literal `TODO` / `FIXME` strings to describe the rule).
///   2. The accepted, issue-referencing form `TODO(#NNN):` / `FIXME(#NNN):`.
final class TodoIssueReferenceTests: XCTestCase {

    /// Absolute path to apps/ios/SoloCompass derived from this file's location:
    /// .../SoloCompass/Tests/TodoIssueReferenceTests.swift → .../SoloCompass
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

    /// Matches a `TODO` / `FIXME` token that is *immediately* followed by the
    /// required issue reference, e.g. `TODO(#123):` or `FIXME(#42):`.
    private let referencedMarker = try! NSRegularExpression(
        pattern: #"(TODO|FIXME)\(#\d+\):"#
    )

    /// Matches any `TODO` / `FIXME` token as a standalone word.
    private let anyMarker = try! NSRegularExpression(
        pattern: #"\b(TODO|FIXME)\b"#
    )

    /// 1-based line numbers in `text` carrying an unreferenced TODO/FIXME.
    private func unreferencedMarkerLines(in text: String) -> [Int] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var offenders: [Int] = []
        for (idx, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            // Strip the accepted, issue-referencing form so a properly tracked
            // marker doesn't count as an offender.
            let stripped = referencedMarker.stringByReplacingMatches(
                in: line, range: range, withTemplate: ""
            )
            let strippedRange = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
            if anyMarker.firstMatch(in: stripped, range: strippedRange) != nil {
                offenders.append(idx + 1)   // 1-based, matching grep -n
            }
        }
        return offenders
    }

    // MARK: - Tests

    /// Sanity check on the matcher itself: the accepted form passes, every
    /// bare form is flagged. Runs without touching the filesystem so it can't
    /// be skipped in a sandboxed host.
    func testMatcherRecognizesReferencedAndBareMarkers() {
        XCTAssertEqual(unreferencedMarkerLines(in: "// TODO(#123): wire this up"), [])
        XCTAssertEqual(unreferencedMarkerLines(in: "// FIXME(#7): flaky"), [])
        XCTAssertEqual(unreferencedMarkerLines(in: "// TODO: untracked").count, 1)
        XCTAssertEqual(unreferencedMarkerLines(in: "// FIXME later").count, 1)
        XCTAssertEqual(unreferencedMarkerLines(in: "// TODO(123): missing hash").count, 1)
    }

    /// Full-tree sweep: every production Swift file (outside `Tests/`) must
    /// have its `TODO`/`FIXME` markers reference a GitHub issue in the
    /// `TODO(#NNN):` form. This is the Swift mirror of the US-053 sweep with
    /// BASELINE = 0.
    func testEveryProductionMarkerReferencesAnIssue() throws {
        let root = appRoot()
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("SoloCompass source not reachable from test host — sandboxed run")
        }

        var offenders: [String] = []
        for fileURL in swiftFiles(under: root) {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for lineNo in unreferencedMarkerLines(in: text) {
                offenders.append("\(fileURL.lastPathComponent):\(lineNo)")
            }
        }

        XCTAssertEqual(
            offenders.count, 0,
            "Unreferenced TODO/FIXME found — resolve it, or file a GitHub issue "
                + "and use the form TODO(#NNN): / FIXME(#NNN): (see US-053). "
                + "Offenders:\n" + offenders.joined(separator: "\n")
        )
    }
}

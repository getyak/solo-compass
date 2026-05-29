import XCTest

/// US-015: Localization coverage guard for the SwiftUI `Views/` layer.
///
/// `scripts/check-hardcoded-strings.sh` is the CLI/CI entry point that audits
/// `Views/` for hardcoded English `Text("X…")` literals. iOS unit-test bundles
/// run in the Simulator sandbox where `Foundation.Process` is unavailable, so
/// this test re-implements the exact same audit in pure Swift — scanning the
/// source tree resolved from `#filePath` — and asserts zero offenders remain.
/// It also asserts the shell script is present and executable so the two stay
/// in lock-step.
final class LocalizationCoverageTest: XCTestCase {

    /// Substrings that, when present on a matched line, are acceptable.
    /// MUST mirror the ALLOWLIST in scripts/check-hardcoded-strings.sh.
    private static let allowlist = [
        #"Text("Solo Compass")"#,   // app brand name (proper noun)
        #"Text("L\("#              // confidence-level badge prefix, e.g. "L1"
    ]

    /// Absolute path to apps/ios/SoloCompass derived from this file's location:
    /// .../SoloCompass/Tests/LocalizationCoverageTest.swift → .../SoloCompass
    private func appRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // SoloCompass/
    }

    private var viewsDir: URL { appRoot().appendingPathComponent("Views") }

    private var scriptPath: URL {
        // .../SoloCompass → .../apps/ios → .../apps → repo root → scripts/
        appRoot()
            .deletingLastPathComponent()   // apps/ios
            .deletingLastPathComponent()   // apps
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("scripts/check-hardcoded-strings.sh")
    }

    private func isAllowlisted(_ line: String) -> Bool {
        Self.allowlist.contains { line.contains($0) }
    }

    /// Replicates the awk pass in the shell script: returns offender lines
    /// (`path:line: code`) that are Text("[A-Z]…") and OUTSIDE #Preview blocks.
    private func offenders(in source: String, path: String) -> [String] {
        var result: [String] = []
        var inPreview = false
        var started = false
        var depth = 0

        for (idx, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine)
            let lineNo = idx + 1

            if line.contains("#Preview") { inPreview = true }

            if inPreview {
                let opens = line.filter { $0 == "{" }.count
                let closes = line.filter { $0 == "}" }.count
                depth += opens
                depth -= closes
                if started && depth <= 0 {
                    inPreview = false; started = false; depth = 0
                } else if opens > 0 {
                    started = true
                }
                continue
            }

            if matchesHardcodedText(line) && !isAllowlisted(line) {
                result.append("\(path):\(lineNo): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        return result
    }

    /// True when the line contains `Text("X` where X is an uppercase ASCII letter.
    private func matchesHardcodedText(_ line: String) -> Bool {
        guard let range = line.range(of: #"Text\("[A-Z]"#, options: .regularExpression) else {
            return false
        }
        _ = range
        return true
    }

    private func swiftFiles(under dir: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    // MARK: - Tests

    func testNoHardcodedEnglishStringsInViews() throws {
        let dir = viewsDir
        guard FileManager.default.fileExists(atPath: dir.path) else {
            throw XCTSkip("Views/ not reachable from test host (\(dir.path)) — sandboxed run")
        }

        var allOffenders: [String] = []
        for fileURL in swiftFiles(under: dir) {
            guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            allOffenders.append(contentsOf: offenders(in: source, path: fileURL.lastPathComponent))
        }

        XCTAssertEqual(
            allOffenders.count, 0,
            "Hardcoded English string(s) in Views/. Replace with NSLocalizedString(...):\n"
                + allOffenders.joined(separator: "\n")
        )
    }

    func testAuditScriptExistsAndIsExecutable() throws {
        let path = scriptPath
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("check-hardcoded-strings.sh not reachable from test host (\(path.path))")
        }
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: path.path),
            "scripts/check-hardcoded-strings.sh must be executable (chmod +x)"
        )
    }
}

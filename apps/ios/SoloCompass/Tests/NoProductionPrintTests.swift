import XCTest

/// US-048: Production `print(...)` ratchet — Swift unit-test mirror of
/// `scripts/check-no-production-print.sh`.
///
/// `print(...)` writes to stdout, can't be filtered in Console.app, and isn't
/// stripped from release builds — so all production logging was migrated to
/// `os.Logger` across US-040 (batch 1) and US-048 (batch 2). This test makes the
/// shell script's ratchet enforceable from the iOS test suite (and CI's iOS job),
/// so a regression fails a unit test rather than only the standalone script.
///
/// Like `ColorExtensionScopeTest` / `LocalizationCoverageTest`, the iOS test
/// bundle runs in the Simulator sandbox where the source tree may be absent, so
/// the audit is re-implemented in pure Swift over the source resolved from
/// `#filePath` and `XCTSkip`s when that tree isn't reachable.
///
/// Two classes of `print(` are intentionally NOT counted, matching the script:
///   1. Lines inside a `#Preview { … }` block (developer scaffolding, never shipped).
///   2. Anything under a `Tests/` directory (test diagnostics, not production code).
final class NoProductionPrintTests: XCTestCase {

    /// Absolute path to apps/ios/SoloCompass derived from this file's location:
    /// .../SoloCompass/Tests/NoProductionPrintTests.swift → .../SoloCompass
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

    /// Count production `print(` occurrences in `text`, skipping lines that fall
    /// inside a `#Preview { … }` block. This mirrors the awk brace-depth tracking
    /// in `scripts/check-no-production-print.sh` so the two stay in lockstep.
    private func productionPrintLines(in text: String) -> [Int] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var offenders: [Int] = []
        var inPreview = false
        var started = false
        var depth = 0

        for (idx, line) in lines.enumerated() {
            if line.contains("#Preview") { inPreview = true }
            if inPreview {
                let opens = line.filter { $0 == "{" }.count
                let closes = line.filter { $0 == "}" }.count
                depth += opens - closes
                if started && depth <= 0 {
                    inPreview = false
                    started = false
                    depth = 0
                } else if opens > 0 {
                    started = true
                }
                continue
            }
            if line.contains("print(") {
                offenders.append(idx + 1)   // 1-based, matching the script
            }
        }
        return offenders
    }

    // MARK: - Tests

    /// Loads a known former offender's containing file (`SubscriptionService.swift`,
    /// the last `print(` migrated in US-048 batch 2) and runs the same `print(`
    /// audit at test-time. Asserts it now has zero production `print(`.
    func testKnownOffenderFileHasNoProductionPrint() throws {
        let url = appRoot().appendingPathComponent("Services/SubscriptionService.swift")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("SubscriptionService.swift not reachable from test host — sandboxed run")
        }
        let offenders = productionPrintLines(in: text)
        XCTAssertEqual(
            offenders, [],
            "SubscriptionService.swift must use os.Logger, not print(). "
                + "Offending line numbers: \(offenders)"
        )
    }

    /// Full-tree sweep: no production Swift file (outside Tests/ and #Preview
    /// blocks) may contain a `print(` call. This is the Swift mirror of
    /// `scripts/check-no-production-print.sh` with BASELINE=0.
    func testNoProductionPrintAnywhere() throws {
        let root = appRoot()
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("SoloCompass source not reachable from test host — sandboxed run")
        }

        var offenders: [String] = []
        for fileURL in swiftFiles(under: root) {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for lineNo in productionPrintLines(in: text) {
                offenders.append("\(fileURL.lastPathComponent):\(lineNo)")
            }
        }

        XCTAssertEqual(
            offenders.count, 0,
            "Production print() found — migrate to os.Logger (see "
                + "scripts/check-no-production-print.sh). Offenders:\n"
                + offenders.joined(separator: "\n")
        )
    }
}

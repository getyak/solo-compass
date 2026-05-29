import XCTest

/// US-037: Availability guard for iOS 18-only symbol effects.
///
/// The app's deployment target is iOS 17.0 (`IPHONEOS_DEPLOYMENT_TARGET: 17.0`
/// in `project.yml`). The `.bounce` symbol effect used with a *repeating*
/// option (`.symbolEffect(.bounce, options: .repeating…)`) relies on the
/// `IndefiniteSymbolEffect` conformance of `.bounce`, which is **iOS 18+**.
/// When such a call is not wrapped in `if #available(iOS 18, *)`, `xcodebuild`
/// emits a warning like:
///
///     'symbolEffect(_:options:isActive:)' is only available in iOS 18.0 or newer
///
/// The canonical check is to run `xcodebuild` and grep its output for that
/// string. iOS unit-test bundles run in the Simulator sandbox where
/// `Foundation.Process` (and therefore invoking `xcodebuild`) is unavailable,
/// so — consistent with `LocalizationCoverageTest` — this test re-implements the
/// audit in pure Swift: it scans the source tree resolved from `#filePath` for
/// every iOS-18-only symbol-effect call site and asserts each one is gated
/// behind an `#available(iOS 18, *)` guard. A `xcodebuild` warning fires exactly
/// when one of these sites is unguarded, so zero unguarded sites ⇒ zero related
/// warnings. This is a best-effort heuristic, not a parse of compiler output.
final class IOS18AvailabilityGuardTest: XCTestCase {

    /// Absolute path to apps/ios/SoloCompass derived from this file's location:
    /// .../SoloCompass/Tests/IOS18AvailabilityGuardTest.swift → .../SoloCompass
    private func appRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // SoloCompass/
    }

    /// Lines that use an iOS-18-only indefinite symbol effect. Today that is the
    /// repeating `.bounce` (`IndefiniteSymbolEffect`). `.symbolEffect(_:value:)`
    /// (discrete) and `.variableColor`/`.pulse` with `isActive:` are iOS 17 and
    /// are intentionally NOT flagged.
    private func isIOS18OnlySymbolEffect(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        guard !stripped.hasPrefix("//") && !stripped.hasPrefix("///") else { return false }
        return line.contains("symbolEffect(.bounce, options:") && line.contains(".repeating")
    }

    /// True when an `#available(iOS 18` guard appears on `lineIdx` or within the
    /// few lines preceding it — covering both `if #available` / `else if
    /// #available` blocks and `if #available(...) else { return }` early guards.
    private func isGuarded(lines: [String], lineIdx: Int) -> Bool {
        let lookback = 6
        let start = max(0, lineIdx - lookback)
        for i in start...lineIdx {
            if lines[i].contains("#available(iOS 18") {
                return true
            }
        }
        return false
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

    // MARK: - Tests

    /// Every iOS-18-only symbol-effect call site must be behind an
    /// `#available(iOS 18, *)` guard. Unguarded sites are exactly what produces
    /// the "available only in iOS 18" warning under our iOS 17 deployment target.
    func testNoUnguardediOS18SymbolEffects() throws {
        let root = appRoot()
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("SoloCompass source not reachable from test host (\(root.path)) — sandboxed run")
        }

        var unguarded: [String] = []
        for fileURL in swiftFiles(under: root) {
            guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (idx, line) in lines.enumerated() where isIOS18OnlySymbolEffect(line) {
                if !isGuarded(lines: lines, lineIdx: idx) {
                    unguarded.append("\(fileURL.lastPathComponent):\(idx + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertEqual(
            unguarded.count, 0,
            "iOS 18-only symbol effect(s) not gated behind `if #available(iOS 18, *)`. "
                + "Each of these would emit an 'available only in iOS 18' xcodebuild warning:\n"
                + unguarded.joined(separator: "\n")
        )
    }

    /// Sanity check on the scanner itself: the known iOS-18 call site
    /// (US-012's repeating `.bounce` in `FavoritesListView`) is present and is
    /// guarded — so the audit is actually exercising a real match rather than
    /// passing vacuously because the pattern was renamed away.
    func testKnownIOS18SiteIsDetectedAndGuarded() throws {
        let fileURL = appRoot()
            .appendingPathComponent("Views/Shared/FavoritesListView.swift")
        guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw XCTSkip("FavoritesListView.swift not reachable from test host — sandboxed run")
        }
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let matchIdx = lines.firstIndex(where: isIOS18OnlySymbolEffect)
        let idx = try XCTUnwrap(
            matchIdx,
            "Expected the repeating `.bounce` symbol effect in FavoritesListView; "
                + "if it was removed, drop this sanity check too."
        )
        XCTAssertTrue(
            isGuarded(lines: lines, lineIdx: idx),
            "The repeating `.bounce` in FavoritesListView must stay behind `#available(iOS 18, *)`."
        )
    }
}

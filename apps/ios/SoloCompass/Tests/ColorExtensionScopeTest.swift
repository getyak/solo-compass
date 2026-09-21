import XCTest

/// US-045: Audit `Color` extensions for unintended public scope.
///
/// The app has exactly ONE hex initializer: the canonical string parser in
/// `Views/Shared/Color+Hex.swift` (`init?(hex: String)`, failable, accepts
/// `"#E8826A"` / `"E8826A"`). A former file-scoped literal helper
/// (`private extension Color { init(hex: UInt32) }` in
/// `Views/Settings/SettingsView.swift`) was removed when Settings moved onto
/// the shared design tokens, so the audit below now enforces that no second
/// hex overload creeps back in — a duplicate parser would drift from the
/// canonical one and reintroduce the ambiguity this story guarded against.
///
/// iOS unit-test bundles run in the Simulator sandbox where the source tree may
/// not be reachable, so — consistent with `IOS18AvailabilityGuardTest` and
/// `LocalizationCoverageTest` — this test re-implements the audit in pure Swift by
/// scanning the source resolved from `#filePath`, and `XCTSkip`s when the tree is
/// not present.
final class ColorExtensionScopeTest: XCTestCase {

    /// Absolute path to apps/ios/SoloCompass derived from this file's location:
    /// .../SoloCompass/Tests/ColorExtensionScopeTest.swift → .../SoloCompass
    private func appRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // SoloCompass/
    }

    private func source(at relativePath: String) throws -> String {
        let url = appRoot().appendingPathComponent(relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("\(relativePath) not reachable from test host — sandboxed run")
        }
        return text
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

    /// The former `Color(hex: UInt32)` literal initializer in `SettingsView.swift`
    /// was removed in favor of the canonical string helper. This ratchet keeps
    /// `SettingsView` from reintroducing a second, local hex parser: any hex
    /// initializer must be declared `private` (file-scoped) if it comes back,
    /// and today it must simply not exist there.
    func testSettingsViewHexInitIsPrivateFileScope() throws {
        let text = try source(at: "Views/Settings/SettingsView.swift")
        XCTAssertFalse(
            text.contains("init(hex:"),
            "SettingsView.swift must not declare a local Color(hex:) initializer — "
                + "extend the canonical Views/Shared/Color+Hex.swift parser instead. "
                + "If a file-scoped helper is ever reintroduced, its enclosing declaration "
                + "must stay `private extension Color`."
        )
    }

    /// `Color(hex: UInt32)` (the numeric-literal overload, e.g. `Color(hex: 0x…)`)
    /// must be referenced ONLY inside `SettingsView.swift`. Any other file calling
    /// it would prove the private extension had leaked (or been duplicated), which
    /// is exactly the unintended-public-scope regression this story guards against.
    func testUInt32HexInitNotUsedOutsideSettingsView() throws {
        let root = appRoot()
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("SoloCompass source not reachable from test host — sandboxed run")
        }

        // Matches `Color(hex: 0x...)` / `Color(hex: 0X...)` — the UInt32-literal form.
        var offenders: [String] = []
        for fileURL in swiftFiles(under: root)
        where fileURL.lastPathComponent != "SettingsView.swift" {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (idx, line) in lines.enumerated()
            where line.contains("Color(hex: 0x") || line.contains("Color(hex: 0X") {
                offenders.append("\(fileURL.lastPathComponent):\(idx + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        XCTAssertEqual(
            offenders.count, 0,
            "The `Color(hex: UInt32)` literal helper is `private` to SettingsView.swift "
                + "and must not be used elsewhere. If you need a global hex initializer, "
                + "add it to Views/Shared/Color+Hex.swift instead of leaking the private one:\n"
                + offenders.joined(separator: "\n")
        )
    }

    /// The canonical, app-wide hex helper is the failable `init?(hex: String)` and
    /// it must live in `Views/Shared/Color+Hex.swift`. This keeps the shared helper
    /// in one place and distinct from the `UInt32` literal variant.
    func testCanonicalStringHexHelperLivesInColorHexFile() throws {
        let text = try source(at: "Views/Shared/Color+Hex.swift")
        XCTAssertTrue(
            text.contains("extension Color"),
            "Color+Hex.swift should declare `extension Color`."
        )
        XCTAssertTrue(
            text.contains("init?(hex: String)"),
            "The canonical hex helper `init?(hex: String)` must live in Views/Shared/Color+Hex.swift."
        )
    }

    /// Sanity check on the scanner: the removed `Color(hex: UInt32)` literal
    /// overload must NOT be reintroduced anywhere in production source. This
    /// replaces the old “call sites still present in SettingsView” check (the
    /// helper was deleted in a refactor) with a ratchet that keeps the canonical
    /// `init?(hex: String)` parser the single hex entry point.
    func testKnownUInt32HexCallSitesPresentInSettingsView() throws {
        let root = appRoot()
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("SoloCompass source not reachable from test host — sandboxed run")
        }

        var offenders: [String] = []
        for fileURL in swiftFiles(under: root) {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (idx, line) in lines.enumerated()
            where line.contains("init(hex: UInt32)")
                || line.contains("Color(hex: 0x")
                || line.contains("Color(hex: 0X") {
                offenders.append("\(fileURL.lastPathComponent):\(idx + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(
            offenders.count, 0,
            "The `Color(hex: UInt32)` literal overload was removed; do not reintroduce "
                + "it (extend the canonical `init?(hex: String)` in Views/Shared/Color+Hex.swift "
                + "instead). Offenders:\n" + offenders.joined(separator: "\n")
        )
    }
}

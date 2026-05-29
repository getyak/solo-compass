import XCTest

/// US-045: Audit `Color` extensions for unintended public scope.
///
/// Two distinct `Color(hex:)` helpers exist in the app, and they must NOT
/// collide or leak across files:
///
/// 1. The **canonical** string parser lives in `Views/Shared/Color+Hex.swift`:
///    `init?(hex: String)` — failable, accepts `"#E8826A"` / `"E8826A"`.
///    This is the shared, app-wide helper (used by e.g. `UserDirectory`).
///
/// 2. A **file-scoped** literal helper lives in `Views/Settings/SettingsView.swift`:
///    `private extension Color { init(hex: UInt32) }` — non-failable, accepts a
///    numeric literal like `0xD4A843`. It is used ONLY inside `SettingsView`.
///
/// Because the two differ by parameter type (`String?` vs `UInt32`) Swift treats
/// them as separate overloads, so even if both were global they would not be
/// ambiguous — but the `UInt32` variant is intentionally `private` so it stays
/// confined to `SettingsView` and cannot collide with a future global hex helper.
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

    /// The `Color(hex: UInt32)` literal initializer in `SettingsView.swift` must
    /// stay behind a `private extension Color` declaration so it is file-scoped
    /// and cannot be accessed from outside `SettingsView`.
    func testSettingsViewHexInitIsPrivateFileScope() throws {
        let text = try source(at: "Views/Settings/SettingsView.swift")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // The opening line is `private extension Color {`; the initializer is on a
        // later line. Locate the `init(hex: UInt32)` then walk back to its
        // enclosing `extension Color` declaration and assert it is `private`.
        let initIdx = try XCTUnwrap(
            lines.firstIndex(where: { $0.contains("init(hex: UInt32)") }),
            "Expected a `Color(hex: UInt32)` initializer in SettingsView.swift; "
                + "if it was removed or renamed, update this audit."
        )
        let openIdx = try XCTUnwrap(
            (0...initIdx).reversed().first(where: { lines[$0].contains("extension Color") }),
            "Found `init(hex: UInt32)` but no enclosing `extension Color` in SettingsView.swift."
        )
        XCTAssertTrue(
            lines[openIdx].contains("private extension Color"),
            "The `Color(hex: UInt32)` helper in SettingsView.swift must be declared "
                + "`private extension Color` so it stays file-scoped. Found: "
                + lines[openIdx].trimmingCharacters(in: .whitespaces)
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

    /// Sanity check on the scanner: the known `Color(hex: 0x…)` call sites inside
    /// SettingsView are still present — so `testUInt32HexInitNotUsedOutsideSettingsView`
    /// is exercising a real, in-use overload rather than passing vacuously because
    /// the helper was deleted.
    func testKnownUInt32HexCallSitesPresentInSettingsView() throws {
        let text = try source(at: "Views/Settings/SettingsView.swift")
        XCTAssertTrue(
            text.contains("Color(hex: 0x"),
            "Expected at least one `Color(hex: 0x…)` call in SettingsView.swift; "
                + "if the UInt32 helper was removed, drop this audit too."
        )
    }
}

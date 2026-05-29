import XCTest

/// US-052: zh-Hans punctuation audit — Swift unit-test mirror of
/// `scripts/check-zh-punctuation.sh`.
///
/// Chinese typography convention uses full-width punctuation (，！？：；（）) in
/// CJK text, not the ASCII half-width forms (,!?:;()). The shell script greps the
/// zh-Hans `Localizable.strings` for half-width marks that sit in a *Chinese
/// context* — directly adjacent to a CJK character — and reports each offender.
///
/// This test re-implements the *same* audit in pure Swift so the ratchet is
/// enforceable from the iOS test suite (and CI's iOS job): a regression fails a
/// unit test, not just the standalone script. Half-width punctuation that is part
/// of a technical value (URLs, `%d`/`%@`/`%1$@` format specifiers, ASCII English)
/// is deliberately left alone — the CJK-adjacency rule is what isolates Chinese
/// prose from those.
///
/// Like `NoProductionPrintTests` / `LocalizationCoverageTest`, the iOS test bundle
/// runs in the Simulator sandbox where the source tree may be absent, so the file
/// is resolved from `#filePath` and the test `XCTSkip`s when that tree isn't
/// reachable.
final class ZhHansPunctuationTest: XCTestCase {

    /// Absolute path to the zh-Hans strings file, derived from this file's
    /// location: .../SoloCompass/Tests/ZhHansPunctuationTest.swift → .../SoloCompass
    private func stringsURL(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // SoloCompass/
            .appendingPathComponent("Resources/zh-Hans.lproj/Localizable.strings")
    }

    /// Half-width marks that have a full-width CJK equivalent. Mirrors the
    /// `[,!?:;()]` class in the shell script.
    private static let halfWidth: Set<Character> = [",", "!", "?", ":", ";", "(", ")"]

    /// Whether `c` counts as a CJK character for adjacency purposes. Mirrors the
    /// script's Perl class: `\p{Han}` plus the CJK symbol/punctuation ranges
    /// already used in the file (、。「」（）！？… etc) and the curly quotes.
    private func isCJK(_ c: Character) -> Bool {
        for scalar in c.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v)        // CJK Unified Ideographs (\p{Han} core)
                || (0x3400...0x4DBF).contains(v)    // CJK Ext A (\p{Han})
                || (0x3000...0x303F).contains(v)    // CJK Symbols and Punctuation
                || (0xFF00...0xFFEF).contains(v)    // Halfwidth/Fullwidth Forms
                || v == 0x2018 || v == 0x2019       // ‘ ’
                || v == 0x201C || v == 0x201D       // “ ”
                || v == 0x2026 {                    // …
                return true
            }
        }
        return false
    }

    /// Extract the quoted value of a `"key" = "value";` line, or nil if the line
    /// isn't a string entry. Mirrors the script's `/=\s*"(.*)"\s*;\s*$/`, tolerating
    /// optional whitespace around the trailing `;`.
    private func value(ofEntryLine line: String) -> String? {
        // Trim trailing whitespace, then require a terminating `;` (\s*;\s*$).
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(";") else { return nil }
        trimmed.removeLast()                                    // drop `;`
        trimmed = String(trimmed.reversed().drop { $0 == " " }.reversed())  // drop `\s*` before `;`
        guard trimmed.hasSuffix("\"") else { return nil }      // must end in closing quote
        guard let eqRange = trimmed.range(of: "=") else { return nil }
        let afterEq = trimmed[eqRange.upperBound...].trimmingCharacters(in: .whitespaces)
        guard afterEq.hasPrefix("\""), afterEq.hasSuffix("\""), afterEq.count >= 2 else { return nil }
        return String(afterEq.dropFirst().dropLast())          // strip the surrounding quotes
    }

    /// True if `value` contains a half-width mark immediately adjacent (either
    /// side) to a CJK character. Mirrors `(?:$cjk$hw|$hw$cjk)`.
    private func hasOffender(in value: String) -> Bool {
        let chars = Array(value)
        for i in chars.indices {
            let c = chars[i]
            guard Self.halfWidth.contains(c) else { continue }
            let prevCJK = i > 0 && isCJK(chars[i - 1])
            let nextCJK = i < chars.count - 1 && isCJK(chars[i + 1])
            if prevCJK || nextCJK { return true }
        }
        return false
    }

    // MARK: - Tests

    /// Runs the same half-width-in-Chinese-context audit the shell script runs and
    /// asserts zero offenders across the zh-Hans `Localizable.strings`.
    func testZhHansHasNoHalfWidthPunctuationInChineseContext() throws {
        let url = stringsURL()
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("zh-Hans Localizable.strings not reachable from test host — sandboxed run")
        }

        var offenders: [String] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for (idx, line) in lines.enumerated() {
            guard let val = value(ofEntryLine: line) else { continue }
            if hasOffender(in: val) {
                offenders.append("\(idx + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        XCTAssertEqual(
            offenders.count, 0,
            "Half-width punctuation found in a Chinese context — use full-width "
                + "equivalents (，！？：；（）). See scripts/check-zh-punctuation.sh. "
                + "Offenders:\n" + offenders.joined(separator: "\n")
        )
    }
}

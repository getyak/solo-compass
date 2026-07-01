import XCTest
@testable import SoloCompass

/// Red-line contract: the Solo Agent MUST NEVER surface a POI it invented
/// (Phase 2 X.4 #X43).
///
/// Every P2.1 tool that returns a place-like payload must draw from the
/// existing `Experience` pool (`MapViewModel.visibleExperiences`), never a
/// hallucinated title/coordinate/description. This is the difference between
/// a helpful concierge and a generator that ships us into "we recommended a
/// café that doesn't exist" territory.
///
/// This suite uses static code scans (grep-of-source) rather than mocks
/// because the guarantee lives in the router source itself — a runtime test
/// would need to enumerate every possible LLM output. Enforcement at source
/// is the only sound frame.
final class NeverInventPOIRedLineTests: XCTestCase {

    /// Absolute path to the tool router. If xcodegen re-layouts this we'll
    /// see a fetch fail rather than a silent pass.
    private var routerSourcePath: String {
        let here = URL(fileURLWithPath: #filePath)
        // .../Tests/NeverInventPOIRedLineTests.swift → .../Services/VoiceAgentToolRouter.swift
        return here
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // SoloCompass/
            .appendingPathComponent("Services/VoiceAgentToolRouter.swift")
            .path
    }

    private func readRouter() throws -> String {
        try String(contentsOfFile: routerSourcePath, encoding: .utf8)
    }

    // MARK: - suggest_now_action must anchor to visibleExperiences

    /// Grab the body of a `private func <name>(...) ... {` block by locating
    /// the declaration and then walking until the next `private ` or `public `
    /// or `internal ` declaration at 4-space indent (which is a sibling
    /// declaration inside the class). This is safer than trying to
    /// brace-match the body's own close-brace, which is at 8-space indent
    /// while sibling handlers' close-brace is at 4-space indent.
    private func handlerBody(named name: String, in src: String) -> String? {
        // Anchor to the DECLARATION, not any call site — `range(of:)` returns
        // the first match, and every handler is also called from the switch.
        // The definition prefix `func <name>(args:` is unique to the decl.
        guard let declRange = src.range(of: "func \(name)(args:") else { return nil }
        let after = String(src[declRange.upperBound...])
        // Next sibling declaration = `\n    private ` at 4-space indent (or
        // `\n}` when we hit the class close). Whichever comes first bounds
        // this handler's body.
        let nextSibling = after.range(of: "\n    private ")?.lowerBound
        let classClose = after.range(of: "\n}")?.lowerBound
        let boundary: String.Index? = {
            switch (nextSibling, classClose) {
            case let (s?, c?): return s < c ? s : c
            case let (s?, nil): return s
            case let (nil, c?): return c
            case (nil, nil): return nil
            }
        }()
        guard let end = boundary else { return nil }
        return String(after[..<end])
    }

    func testSuggestNowActionAnchorsToVisibleExperiences() throws {
        let src = try readRouter()
        guard let body = handlerBody(named: "executeSuggestNowAction", in: src) else {
            return XCTFail("executeSuggestNowAction body not found")
        }

        XCTAssertTrue(body.contains("vm.visibleExperiences"),
                      "suggest_now_action must draw from vm.visibleExperiences (RAG anchor)")
        XCTAssertTrue(body.contains("no_visible_candidates"),
                      "suggest_now_action must return a graceful noop instead of a synthesised POI")
        XCTAssertFalse(body.contains("Experience(id:"),
                       "suggest_now_action must NOT construct a new Experience literal — that's an invented POI")
    }

    // MARK: - bury_capsule must reject unknown content types

    func testBuryCapsuleValidatesContentType() throws {
        let src = try readRouter()
        guard let body = handlerBody(named: "executeBuryCapsule", in: src) else {
            return XCTFail("executeBuryCapsule body not found")
        }
        XCTAssertTrue(body.contains(#""text""#) &&
                      body.contains(#""voice""#) &&
                      body.contains(#""photo""#),
                      "bury_capsule must whitelist text|voice|photo — unknown values leak an invented POI")
    }

    // MARK: - No literal latitude in successJSON payloads

    /// Any handler that emits a JSON payload with a literal `"latitude": 12.34`
    /// pair is a smell — could be echoing back an LLM-invented place. Scan for
    /// that anti-pattern. (Legitimate handlers pass `parsed.latitude` as a
    /// variable, not a string key colon-followed by a decimal literal.)
    func testNoLiteralLatLonInSuccessJSON() throws {
        let src = try readRouter()
        let pattern = #"successJSON\(\[[^]]*"latitude"\s*:\s*\d+\.\d+"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(src.startIndex..., in: src)
        let matches = regex.matches(in: src, options: [], range: range)
        XCTAssertEqual(matches.count, 0,
                       "successJSON must never emit a literal latitude number — that's an invented POI")
    }

    // MARK: - All 7 P2.1 tools present in the switch (contract with recon)

    /// If a tool case is accidentally deleted from the switch, its schema in
    /// `allTools` still advertises the capability to the LLM — but a call
    /// would return `unknownTool` at runtime, silently losing intent. Guard
    /// the switch cases so a rename triggers a test failure, not a mystery.
    func testAllSevenP21ToolsRoutedInSwitch() throws {
        let src = try readRouter()
        let expected = [
            "\"suggest_now_action\"",
            "\"open_blindbox\"",
            "\"bury_capsule\"",
            "\"recall_pattern\"",
            "\"sos_plan\"",
            "\"unwalked_path\"",
            "\"recall_local_scene\"",
        ]
        for name in expected {
            XCTAssertTrue(src.contains("case \(name):"),
                          "switch must route \(name) — advertised via allTools schema")
        }
    }
}

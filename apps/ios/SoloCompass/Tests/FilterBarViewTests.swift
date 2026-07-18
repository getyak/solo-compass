import XCTest
@testable import SoloCompass

/// US-006: FilterBarView pills reflect `UserPreferences.visibleCategories`.
@MainActor
final class FilterBarViewTests: XCTestCase {

    func testDefaultPreferencesIncludeAllEightCategories() {
        let defaults = UserDefaults(suiteName: "us006.default.\(UUID().uuidString)")!
        let prefs = UserPreferences(defaults: defaults)
        XCTAssertEqual(prefs.visibleCategories, Set(ExperienceCategory.allCases))
        XCTAssertEqual(prefs.visibleCategories.count, 8)
    }

    func testRemovingNightlifeDropsNightlifePill() {
        var selection = Set(ExperienceCategory.allCases)
        XCTAssertTrue(FilterBarView.visiblePills(from: selection).contains(.nightlife))

        selection.remove(.nightlife)
        let pills = FilterBarView.visiblePills(from: selection)
        XCTAssertFalse(pills.contains(.nightlife), "nightlife pill must be hidden when removed from visibleCategories")
        XCTAssertEqual(pills.count, 7)
    }

    func testPillOrderMatchesEnumDeclarationOrder() {
        // Subset out of declaration order to prove ordering is by allCases,
        // not by Set iteration.
        let selection: Set<ExperienceCategory> = [.coffee, .culture, .nightlife]
        let pills = FilterBarView.visiblePills(from: selection)
        XCTAssertEqual(pills, [.culture, .coffee, .nightlife])
    }

    func testVisibleCategoriesPersistsAcrossPreferencesReload() {
        let suite = "us006.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = UserPreferences(defaults: defaults)
        var trimmed = Set(ExperienceCategory.allCases)
        trimmed.remove(.nightlife)
        prefs.visibleCategories = trimmed

        let reloaded = UserPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.visibleCategories, trimmed)
        XCTAssertFalse(reloaded.visibleCategories.contains(.nightlife))
    }

    // MARK: - compactCount badge formatter

    func testCompactCountZero() {
        XCTAssertEqual(FilterBarView.compactCount(0), "0")
    }

    func testCompactCountAtLimit() {
        XCTAssertEqual(FilterBarView.compactCount(99), "99")
    }

    func testCompactCountJustOverLimit() {
        XCTAssertEqual(FilterBarView.compactCount(100), "99+")
    }

    func testCompactCountLargeNumber() {
        XCTAssertEqual(FilterBarView.compactCount(1234), "99+")
    }

    // MARK: - Toggle-off routing (pill clear behaviour)

    func testResolvesToClearWhenPillIsSelected() {
        XCTAssertTrue(FilterBarView.resolvesToClear(isSelected: true),
                      "Re-tapping an active pill must resolve to clear")
    }

    func testDoesNotResolveToClearWhenPillIsUnselected() {
        XCTAssertFalse(FilterBarView.resolvesToClear(isSelected: false),
                       "Tapping an inactive pill must not resolve to clear")
    }
}

/// Regression guard for the "Ask Solo" pill's tap action (P2.5 #250).
///
/// History: commit 7a255c3b wired `onSoloAgentTap` to a placeholder —
/// `viewModel.selectNowFilter()` — instead of opening the ChatSheet. With the
/// Now filter already active (the app's common resting state) the tap was a
/// complete no-op: the most prominent AI entry point on the home screen was a
/// dead button. The real action must route through the parent's chat
/// presenter (`ensureOrchestrator`) with the suggest-now seed prompt.
///
/// SwiftUI closures can't be introspected from XCTest, so this scans the
/// source the same way `BottomSheetUnifiedScrollGuardTest` and
/// `NeverInventPOIRedLineTests` do, asserting the structural wiring.
final class AskSoloPillWiringGuardTest: XCTestCase {

    private func mapViewSource() throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let url = here
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // SoloCompass/
            .appendingPathComponent("Views/Map/CompassMapView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The FilterBar hook must forward the parent-supplied closure — never a
    /// filter mutation. `selectNowFilter()` next to `onSoloAgentTap:` is the
    /// exact dead-button regression.
    func testSoloAgentTapDoesNotDegradeToNowFilter() throws {
        let source = try mapViewSource()
        XCTAssertFalse(
            source.contains("onSoloAgentTap: { viewModel.selectNowFilter() }"),
            "Ask Solo pill must open the chat, not silently re-select the Now filter (dead button when Now is already active)"
        )
        XCTAssertTrue(
            source.contains("onSoloAgentTap: onAskSolo"),
            "FilterBarView's onSoloAgentTap must forward MapOverlayView.onAskSolo (the parent's open-chat closure)"
        )
    }

    /// The parent's `onAskSolo` closure must actually present the chat: it
    /// needs both the orchestrator bring-up and the seed prompt that fires
    /// the suggest_now_action shortcut the pill promises.
    func testOnAskSoloOpensChatWithSeedPrompt() throws {
        let source = try mapViewSource()
        guard let range = source.range(of: "onAskSolo: {") else {
            return XCTFail("CompassMapContentView must pass an onAskSolo closure to MapOverlayView")
        }
        let body = String(source[range.upperBound...].prefix(600))
        XCTAssertTrue(
            body.contains("ensureOrchestrator(viewModel: viewModel)"),
            "onAskSolo must bring up the chat orchestrator (this is what presents the ChatSheet)"
        )
        XCTAssertTrue(
            body.contains("filter.solo.agent.seed"),
            "onAskSolo must seed the suggest-now prompt so the agent answers immediately"
        )
    }
}

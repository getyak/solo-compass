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

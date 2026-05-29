import XCTest
import SwiftUI
@testable import SoloCompass

/// US-050: Empty-state views (FilterBarView empty result, BottomInfoSheet empty
/// Nearby list) must announce themselves to VoiceOver on appear so users don't
/// assume the UI froze. These tests assert the announcement plumbing exists:
/// every empty state exposes a localized announcement key that resolves to real
/// text, and the empty-state views are constructible and carry that text.
final class EmptyStateAnnouncementTest: XCTestCase {

    /// Loads the English Localizable.strings from the test bundle the same way
    /// StringsParityTests does, so we assert against the shipped keys rather
    /// than relying on the test host's main-bundle lookup.
    private func englishStrings() -> [String: String]? {
        guard let url = Bundle(for: type(of: self)).url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: nil,
            localization: "en"
        ) else { return nil }
        return NSDictionary(contentsOf: url) as? [String: String]
    }

    // MARK: - Keys exist and resolve

    func testEmptyAnnouncementKeysExistInEnglish() {
        guard let english = englishStrings() else {
            return XCTFail("Missing English Localizable.strings")
        }
        for key in [
            FilterBarView.emptyResultsAnnouncementKey,
            EmptySheetListView.announcementKey,
            "a11y.empty.list"
        ] {
            XCTAssertNotNil(english[key], "Missing empty-state announcement key: \(key)")
            XCTAssertFalse(
                english[key]?.isEmpty ?? true,
                "Empty-state announcement key has empty value: \(key)"
            )
        }
    }

    func testFilterBarEmptyAnnouncementKeyIsStable() {
        // The announcement key the view posts must match the localized key, so
        // the modifier announces real text and not a raw key string.
        XCTAssertEqual(FilterBarView.emptyResultsAnnouncementKey, "a11y.empty.filterResults")
    }

    func testSheetEmptyAnnouncementKeyIsStable() {
        XCTAssertEqual(EmptySheetListView.announcementKey, "a11y.empty.nearby")
    }

    // MARK: - View tree carries the announcement modifier

    /// The empty-state views must be constructible and expose the localized
    /// announcement text that the `.onAppear { UIAccessibility.post(...) }`
    /// modifier posts. Reflecting the SwiftUI body verifies the empty view is
    /// what the section renders when there are no experiences.
    func testEmptySheetListViewExposesLocalizedAnnouncement() {
        let view = EmptySheetListView()
        XCTAssertFalse(
            view.localizedEmptyText.isEmpty,
            "EmptySheetListView must expose non-empty announcement text"
        )
        // The resolved text must differ from the raw key (i.e. it was found in
        // the strings table), otherwise VoiceOver would read the key aloud.
        XCTAssertNotEqual(view.localizedEmptyText, EmptySheetListView.announcementKey)
    }

    func testFilterBarViewExposesLocalizedAnnouncement() {
        let view = FilterBarView(
            selectedCategory: nil,
            isNowSelected: false,
            onSelectNow: {},
            onSelectAll: {},
            onSelectCategory: { _ in }
        )
        XCTAssertFalse(
            view.localizedEmptyText.isEmpty,
            "FilterBarView must expose non-empty empty-results announcement text"
        )
        XCTAssertNotEqual(view.localizedEmptyText, FilterBarView.emptyResultsAnnouncementKey)
    }

    /// When the Nearby section has no experiences it must render the empty-state
    /// view (which carries the announcement), not the experience list. We
    /// evaluate `NearbySection.body` once (it has no environment dependencies,
    /// so this is safe) and walk the resulting view graph with Mirror — without
    /// touching primitive views' bodies — looking for the EmptySheetListView and
    /// confirming the experience-list branch (NearbyExperienceRow) is absent.
    func testNearbySectionRendersEmptyStateWhenNoExperiences() {
        let section = NearbySection(
            experiences: [],
            smartPickIds: [],
            referenceCoordinate: nil,
            onSelectExperience: { _ in }
        )
        let tree = section.body
        XCTAssertTrue(
            Self.viewTreeContains(tree, typeName: "EmptySheetListView"),
            "NearbySection with no experiences must render EmptySheetListView so VoiceOver is announced"
        )
        XCTAssertFalse(
            Self.viewTreeContains(tree, typeName: "NearbyExperienceRow"),
            "Empty NearbySection must not render the experience-list branch"
        )
    }

    // MARK: - Reflection helper

    /// Recursive Mirror walk that returns true if any node in the reflected
    /// structure has a type whose name contains `typeName`. This only inspects
    /// Mirror children — it never evaluates a SwiftUI `body` — so it is safe to
    /// run against trees containing primitive views (Text/Image) whose body is
    /// `Never` and would trap if accessed.
    private static func viewTreeContains(_ root: Any, typeName: String, depth: Int = 0) -> Bool {
        if depth > 60 { return false }
        let mirror = Mirror(reflecting: root)
        if String(describing: mirror.subjectType).contains(typeName) {
            return true
        }
        for child in mirror.children {
            if viewTreeContains(child.value, typeName: typeName, depth: depth + 1) {
                return true
            }
        }
        return false
    }
}

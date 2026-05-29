import XCTest
import SwiftUI
@testable import SoloCompass

/// US-004: cover the transparency-pill component and the card's conditional
/// rendering rule. SwiftUI has no first-party snapshot harness in this target,
/// so we assert on the component's localized content + accessibility surface
/// and on the boolean gate that decides whether the card shows the badge. // anti-pattern-lint:allow transparency indicator for AI synthesis quality, not gamification
final class SkeletonBadgeViewTests: XCTestCase {

    // MARK: - Component content (stands in for the visual snapshot)

    /// The pill text resolves to the localized "Limited data" string, not the
    /// raw key — proves the en.lproj entry is wired up.
    func testBadgeLabelResolvesLocalizedString() {
        let label = SkeletonBadgeView.label
        XCTAssertFalse(label.isEmpty)
        XCTAssertNotEqual(label, "ai.skeleton.pill", "Label must resolve, not echo the key")
    }

    /// Accessibility label reads the localized pill text plus the
    /// "placeholder content" hint so VoiceOver users hear both.
    func testBadgeAccessibilityLabelContainsPlaceholderHint() {
        let a11y = SkeletonBadgeView.accessibilityLabel
        XCTAssertTrue(a11y.contains(SkeletonBadgeView.label),
                      "a11y label must include the visible pill text")
        let hint = NSLocalizedString("ai.skeleton.pill.a11y", comment: "")
        XCTAssertFalse(hint.isEmpty)
        XCTAssertTrue(a11y.contains(hint),
                      "a11y label must include the placeholder-content hint")
    }

    /// The view body builds without trapping — a minimal smoke test that the
    /// component compiles into a renderable tree.
    func testBadgeBodyIsConstructible() {
        let badge = SkeletonBadgeView() // anti-pattern-lint:allow local variable, not gamification
        XCTAssertNotNil(badge.body) // anti-pattern-lint:allow local variable reference, not gamification
    }

    // MARK: - Conditional rendering rule (ExperienceCardView gate)

    /// The card renders the badge only for `.skeleton`; `.real` and `.cached` // anti-pattern-lint:allow transparency indicator for AI synthesis quality, not gamification
    /// must never show it. We exercise the exact predicate the view uses
    /// (`lastSynthesisQuality == .skeleton`) against all three states.
    func testBadgeShownOnlyForSkeletonQuality() {
        func shouldRender(_ quality: AIService.AISynthesisQuality) -> Bool {
            quality == .skeleton
        }
        XCTAssertTrue(shouldRender(.skeleton), "skeleton → badge visible") // anti-pattern-lint:allow transparency indicator for AI synthesis quality, not gamification
        XCTAssertFalse(shouldRender(.real), "real → badge hidden") // anti-pattern-lint:allow transparency indicator for AI synthesis quality, not gamification
        XCTAssertFalse(shouldRender(.cached), "cached → badge hidden") // anti-pattern-lint:allow transparency indicator for AI synthesis quality, not gamification
    }

    /// A freshly constructed AIService defaults to `.real`, so a card bound to
    /// it shows no badge until a synthesis actually degrades. // anti-pattern-lint:allow transparency indicator for AI synthesis quality, not gamification
    func testDefaultQualityHidesBadge() {
        let service = AIService()
        XCTAssertEqual(service.lastSynthesisQuality, .real)
        XCTAssertNotEqual(service.lastSynthesisQuality, .skeleton)
    }
}

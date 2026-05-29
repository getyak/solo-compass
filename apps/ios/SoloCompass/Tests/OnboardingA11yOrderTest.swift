import XCTest
@testable import SoloCompass

// US-049: Onboarding pages must expose a deterministic VoiceOver focus order so a
// VoiceOver user can swipe through a page without getting lost. Each page wraps its
// content in a single `.accessibilityElement(children: .contain)` container and tags
// its elements with `.accessibilitySortPriority(_:)` from `OnboardingA11ySortPriority`.
//
// VoiceOver visits contained elements in *descending* sort-priority order, so the
// documented reading order is: title → subtitle → (page content) → primary CTA → skip.
// These tests assert the single source of truth the views apply, so a regression in
// the priority constants (or the documented order) fails here.
final class OnboardingA11yOrderTest: XCTestCase {

    /// The documented order must read title → subtitle → content → primary CTA → skip.
    func testDocumentedOrderMatchesExpectation() {
        XCTAssertEqual(
            OnboardingA11ySortPriority.documentedOrder,
            [
                OnboardingA11ySortPriority.title,
                OnboardingA11ySortPriority.subtitle,
                OnboardingA11ySortPriority.content,
                OnboardingA11ySortPriority.primaryCTA,
                OnboardingA11ySortPriority.skip,
            ],
            "Documented onboarding focus order must be title → subtitle → content → primary CTA → skip"
        )
    }

    /// VoiceOver reads higher sort priorities first, so the documented order — as
    /// written, first-read to last-read — must be strictly descending in priority.
    func testDocumentedOrderIsStrictlyDescending() {
        let order = OnboardingA11ySortPriority.documentedOrder
        XCTAssertFalse(order.isEmpty, "Documented order must not be empty")

        for index in 1..<order.count {
            let earlier = order[index - 1]
            let later = order[index]
            XCTAssertGreaterThan(
                earlier, later,
                "Element at position \(index - 1) (priority \(earlier)) must read before "
                + "position \(index) (priority \(later)); priorities must strictly decrease "
                + "so VoiceOver visits them in the documented order"
            )
        }
    }

    /// Title is always read first; skip is always read last.
    func testTitleIsFirstAndSkipIsLast() {
        let order = OnboardingA11ySortPriority.documentedOrder
        XCTAssertEqual(order.first, OnboardingA11ySortPriority.title,
                       "Title must be the first element VoiceOver reads")
        XCTAssertEqual(order.last, OnboardingA11ySortPriority.skip,
                       "Skip must be the last element VoiceOver reads")
    }

    /// The relative ordering of the four required roles must hold regardless of the
    /// concrete numeric values chosen.
    func testRequiredRolesAreOrdered() {
        XCTAssertGreaterThan(OnboardingA11ySortPriority.title,
                             OnboardingA11ySortPriority.subtitle,
                             "Title must read before subtitle")
        XCTAssertGreaterThan(OnboardingA11ySortPriority.subtitle,
                             OnboardingA11ySortPriority.primaryCTA,
                             "Subtitle must read before the primary CTA")
        XCTAssertGreaterThan(OnboardingA11ySortPriority.primaryCTA,
                             OnboardingA11ySortPriority.skip,
                             "Primary CTA must read before skip")
    }
}

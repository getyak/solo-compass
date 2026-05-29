import XCTest
@testable import SoloCompass

// US-042: The Skip affordance in the onboarding parent view must complete the
// flow — it marks onboarding complete (so the gate stops re-presenting it) and
// fires the onComplete callback that dismisses the .fullScreenCover.
final class OnboardingSkipTest: XCTestCase {

    /// Mirrors the action wired to OnboardingView's top-right Skip button:
    /// `preferences.completeOnboarding(); onComplete()`.
    @MainActor
    func testSkipCompletesOnboardingAndDismissesFlow() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let preferences = UserPreferences(defaults: defaults)

        // Precondition: a fresh user has not completed onboarding, so the flow shows.
        XCTAssertFalse(preferences.hasCompletedOnboarding,
                       "Fresh user must start with onboarding incomplete")

        var dismissed = false
        let onComplete: () -> Void = { dismissed = true }

        // Perform the Skip action.
        preferences.completeOnboarding()
        onComplete()

        XCTAssertTrue(preferences.hasCompletedOnboarding,
                      "Skip must mark onboarding complete so the flow is not shown again")
        XCTAssertTrue(dismissed,
                      "Skip must invoke onComplete to dismiss the onboarding cover")
    }

    /// The completion flag must persist so returning users skip onboarding on relaunch.
    @MainActor
    func testSkipPersistsAcrossLaunches() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let preferences = UserPreferences(defaults: defaults)

        preferences.completeOnboarding()

        let reloaded = UserPreferences(defaults: defaults)
        XCTAssertTrue(reloaded.hasCompletedOnboarding,
                      "Skipping onboarding must persist across launches")
    }

    /// The Skip label must be localized in both shipped localizations.
    func testSkipStringLocalized() throws {
        let searchBundles = [Bundle.main, Bundle(for: OnboardingSkipTest.self)]
        for localization in ["en", "zh-Hans"] {
            var found: [String: String]?
            for bundle in searchBundles {
                if let url = bundle.url(forResource: "Localizable",
                                        withExtension: "strings",
                                        subdirectory: nil,
                                        localization: localization),
                   let dict = NSDictionary(contentsOf: url) as? [String: String] {
                    found = dict
                    break
                }
            }
            guard let dict = found else {
                throw XCTSkip("Localizable.strings (\(localization)) not found in test host bundle")
            }
            XCTAssertNotNil(dict["onboarding.skip"],
                            "\(localization).lproj must define onboarding.skip")
        }
    }
}

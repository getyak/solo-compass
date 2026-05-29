import XCTest
@testable import SoloCompass

// US-044: Regression coverage for SettingsView's language-switch flow. The
// Language section lists LanguageService.Option rows; tapping one runs:
//
//     if languageService.setLanguage(option) {
//         showingLanguageRestartAlert = true
//     }
//
// i.e. a *real* language change schedules the app-restart prompt (the alert
// keyed off `showingLanguageRestartAlert`), while re-selecting the current
// language is a no-op and does NOT prompt. These tests reproduce that exact
// gate against the live LanguageService without modifying behavior.
@MainActor
final class SettingsLanguageSwitchRestartTest: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsLanguageSwitchRestartTest-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Mirrors SettingsView's language row onTapGesture: switch the language
    /// and, when it actually changed, flip the restart-alert flag. The bool
    /// returned here stands in for SettingsView's `showingLanguageRestartAlert`
    /// @State.
    private func tapLanguageRow(
        _ option: LanguageService.Option,
        on service: LanguageService,
        showingRestartAlert: inout Bool
    ) {
        if service.setLanguage(option) {
            showingRestartAlert = true
        }
    }

    func testSwitchingLanguageSchedulesRestartPrompt() {
        let service = LanguageService(defaults: defaults)
        XCTAssertEqual(service.current, .system, "Precondition: fresh service follows system")

        var showingRestartAlert = false
        tapLanguageRow(.simplifiedChinese, on: service, showingRestartAlert: &showingRestartAlert)

        XCTAssertTrue(showingRestartAlert,
                      "Changing the language must schedule the app-restart prompt")
        XCTAssertEqual(service.current, .simplifiedChinese,
                       "The selected language must be applied")
    }

    func testReselectingCurrentLanguageDoesNotPrompt() {
        let service = LanguageService(defaults: defaults)
        // Land on English first (this would have prompted).
        _ = service.setLanguage(.english)

        var showingRestartAlert = false
        // Tapping the already-active language again is a no-op.
        tapLanguageRow(.english, on: service, showingRestartAlert: &showingRestartAlert)

        XCTAssertFalse(showingRestartAlert,
                       "Re-selecting the active language must NOT schedule a restart prompt")
        XCTAssertEqual(service.current, .english)
    }

    func testEachDistinctSwitchReschedulesPrompt() {
        let service = LanguageService(defaults: defaults)

        var firstSwitch = false
        tapLanguageRow(.english, on: service, showingRestartAlert: &firstSwitch)
        XCTAssertTrue(firstSwitch, "system → English is a real change and must prompt")

        var secondSwitch = false
        tapLanguageRow(.simplifiedChinese, on: service, showingRestartAlert: &secondSwitch)
        XCTAssertTrue(secondSwitch, "English → 简体中文 is a real change and must prompt again")
        XCTAssertEqual(service.current, .simplifiedChinese)
    }

    /// The restart alert's strings must exist in both shipped localizations so
    /// the prompt SettingsView presents is never a raw key.
    func testRestartPromptStringsLocalized() throws {
        let searchBundles = [Bundle.main, Bundle(for: SettingsLanguageSwitchRestartTest.self)]
        let restartKeys = [
            "settings.language.restart.title",
            "settings.language.restart.message",
            "settings.language.restart.ok",
        ]
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
            for key in restartKeys {
                XCTAssertNotNil(dict[key], "\(localization).lproj must define \(key)")
            }
        }
    }
}

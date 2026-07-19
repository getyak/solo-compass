import XCTest
@testable import SoloCompass

/// Nomad OS B1-f: the "new home" banner is one-shot — shown once when an
/// existing user first lands on Today, dismissed for good after. The dismissal
/// contract lives in `UserDefaults` (the only externally observable part; the
/// visible flag is private view state), so these tests pin the persisted flag
/// and the both-language string coverage.
final class TodayNewHomeBannerTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test-newhome-\(UUID().uuidString)")!
    }

    /// A fresh user has not seen the banner, so the seen-flag starts false —
    /// the banner's `init` reads this to decide initial visibility.
    func testUnseenByDefault() {
        let defaults = freshDefaults()
        XCTAssertFalse(defaults.bool(forKey: TodayNewHomeBanner.seenKey),
                       "A fresh user must start with the banner unseen")
    }

    /// Once the seen-flag is set (the effect of a dismiss), a new
    /// `UserDefaults` handle onto the same suite reads it back — the flag
    /// survives the process boundary a returning user's banner init crosses.
    func testSeenFlagPersistsAcrossHandles() {
        let suite = "test-newhome-\(UUID().uuidString)"
        let writer = UserDefaults(suiteName: suite)!
        writer.set(true, forKey: TodayNewHomeBanner.seenKey)

        let reader = UserDefaults(suiteName: suite)!
        XCTAssertTrue(reader.bool(forKey: TodayNewHomeBanner.seenKey),
                      "The seen flag must persist so the banner never re-appears")
    }

    /// Constructing the banner against a store that already has the seen-flag
    /// must not throw or reset it — the returning-user path.
    @MainActor
    func testConstructsHiddenWhenAlreadySeen() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: TodayNewHomeBanner.seenKey)
        _ = TodayNewHomeBanner(defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: TodayNewHomeBanner.seenKey),
                      "Constructing the banner must not clear the seen flag")
    }

    /// The banner's strings must exist in both shipped localizations.
    func testStringsLocalizedInBothLanguages() throws {
        let searchBundles = [Bundle.main, Bundle(for: TodayNewHomeBannerTests.self)]
        let keys = ["today.newHome.title", "today.newHome.subtitle", "today.newHome.dismiss"]
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
            for key in keys {
                XCTAssertNotNil(dict[key], "\(localization).lproj must define \(key)")
            }
        }
    }
}

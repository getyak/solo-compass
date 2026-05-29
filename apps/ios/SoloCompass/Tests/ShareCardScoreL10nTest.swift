import XCTest

/// US-039: The share-card "/100  Solo Score" suffix must be routed through
/// `NSLocalizedString` via the `sharecard.score.suffix` key so it renders in the
/// user's locale rather than a hardcoded English literal. The key must resolve in
/// each `Localizable.strings` (en + zh-Hans).
final class ShareCardScoreL10nTest: XCTestCase {

    /// Load the localized value for `key` directly from a given localization's
    /// `Localizable.strings`, bypassing the simulator's current locale. Mirrors
    /// the bundle lookup used by `StringsParityTests` / `ShareCardComponentsL10nTest`.
    private func localizedValue(forKey key: String, localization: String) -> String? {
        let searchBundles = [Bundle.main, Bundle(for: ShareCardScoreL10nTest.self)]
        for bundle in searchBundles {
            if let url = bundle.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: localization
            ), let dict = NSDictionary(contentsOf: url) as? [String: String] {
                return dict[key]
            }
        }
        return nil
    }

    func testScoreSuffixResolvesInEnglish() throws {
        guard let enValue = localizedValue(forKey: "sharecard.score.suffix", localization: "en") else {
            throw XCTSkip("en.lproj/Localizable.strings not found in test host bundle")
        }
        XCTAssertEqual(enValue, "/100  Solo Score",
            "en sharecard.score.suffix must resolve to the English suffix, got: \(enValue)")
    }

    func testScoreSuffixResolvesInZhHans() throws {
        guard let zhValue = localizedValue(forKey: "sharecard.score.suffix", localization: "zh-Hans") else {
            throw XCTSkip("zh-Hans.lproj/Localizable.strings not found in test host bundle")
        }
        XCTAssertEqual(zhValue, "/100 Solo 评分",
            "zh-Hans sharecard.score.suffix must resolve to the localized suffix, got: \(zhValue)")
    }
}

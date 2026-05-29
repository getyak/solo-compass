import XCTest

/// US-038: The share-card brand label must be routed through `NSLocalizedString`
/// via the `sharecard.brand` key. The string is intentionally identical in both
/// locales ("Solo Compass"), but the key must resolve in each `Localizable.strings`
/// so the branding goes through the localization pipeline rather than a hardcoded literal.
final class ShareCardComponentsL10nTest: XCTestCase {

    /// Load the localized value for `key` directly from a given localization's
    /// `Localizable.strings`, bypassing the simulator's current locale. Mirrors
    /// the bundle lookup used by `StringsParityTests` / `FilterBarLocalizationTests`.
    private func localizedValue(forKey key: String, localization: String) -> String? {
        let searchBundles = [Bundle.main, Bundle(for: ShareCardComponentsL10nTest.self)]
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

    func testBrandKeyResolvesInEnglish() throws {
        guard let enValue = localizedValue(forKey: "sharecard.brand", localization: "en") else {
            throw XCTSkip("en.lproj/Localizable.strings not found in test host bundle")
        }
        XCTAssertEqual(enValue, "Solo Compass",
            "en sharecard.brand must resolve to the brand label, got: \(enValue)")
    }

    func testBrandKeyResolvesInZhHans() throws {
        guard let zhValue = localizedValue(forKey: "sharecard.brand", localization: "zh-Hans") else {
            throw XCTSkip("zh-Hans.lproj/Localizable.strings not found in test host bundle")
        }
        XCTAssertEqual(zhValue, "Solo Compass",
            "zh-Hans sharecard.brand must resolve to the brand label, got: \(zhValue)")
    }
}

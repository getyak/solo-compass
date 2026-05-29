import XCTest

// US-042: Verify en.lproj and zh-Hans.lproj Localizable.strings have the same key set.
final class StringsParityTests: XCTestCase {

    private func loadKeys(localization: String) -> Set<String>? {
        // The .strings files live in the app bundle (the test host), not the test bundle.
        let searchBundles = [Bundle.main, Bundle(for: StringsParityTests.self)]
        for bundle in searchBundles {
            if let url = bundle.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: localization
            ), let dict = NSDictionary(contentsOf: url) as? [String: String] {
                return Set(dict.keys)
            }
        }
        return nil
    }

    func testEnAndZhHansHaveSameKeys() throws {
        guard let enKeys = loadKeys(localization: "en") else {
            // If we can't find the file in the bundle (simulator locale mismatch), skip gracefully.
            throw XCTSkip("en.lproj/Localizable.strings not found in test host bundle")
        }
        guard let zhKeys = loadKeys(localization: "zh-Hans") else {
            throw XCTSkip("zh-Hans.lproj/Localizable.strings not found in test host bundle")
        }

        XCTAssertFalse(enKeys.isEmpty, "en.lproj/Localizable.strings must not be empty")
        XCTAssertFalse(zhKeys.isEmpty, "zh-Hans.lproj/Localizable.strings must not be empty")

        let onlyInEn = enKeys.subtracting(zhKeys).sorted()
        let onlyInZh = zhKeys.subtracting(enKeys).sorted()

        XCTAssertTrue(onlyInEn.isEmpty,
            "Keys in en but missing in zh-Hans (\(onlyInEn.count)):\n\(onlyInEn.joined(separator: "\n"))")
        XCTAssertTrue(onlyInZh.isEmpty,
            "Keys in zh-Hans but missing in en (\(onlyInZh.count)):\n\(onlyInZh.joined(separator: "\n"))")
    }

    /// US-004: the SkeletonBadgeView keys must be present in both localizations.
    func testSkeletonBadgeKeysPresentInBothLocalizations() throws {
        guard let enKeys = loadKeys(localization: "en"),
              let zhKeys = loadKeys(localization: "zh-Hans") else {
            throw XCTSkip("Localizable.strings not found in test host bundle")
        }
        for key in ["ai.skeleton.pill", "ai.skeleton.pill.a11y"] {
            XCTAssertTrue(enKeys.contains(key), "en.lproj missing \(key)")
            XCTAssertTrue(zhKeys.contains(key), "zh-Hans.lproj missing \(key)")
        }
    }
}

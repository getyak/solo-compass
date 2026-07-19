import XCTest
@testable import SoloCompass

/// Nomad OS B1-e: the onboarding cohort step captures the traveler's
/// city-change frequency band into `UserPreferences.nomadCohort`. These tests
/// pin the persistence round-trip, the raw-string degrade path, the
/// selectable-cases contract the step relies on, and the two-localization
/// coverage of the step's strings.
final class NomadCohortTests: XCTestCase {

    // MARK: Persistence

    /// Selecting a band writes through `persist()` and survives a reload — the
    /// signal must not be lost if the user force-quits before finishing.
    @MainActor
    func testCohortPersistsAcrossLaunches() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let preferences = UserPreferences(defaults: defaults)

        XCTAssertEqual(preferences.nomadCohort, .unset,
                       "A fresh user must start with no cohort signal")

        preferences.nomadCohort = .active

        let reloaded = UserPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.nomadCohort, .active,
                       "The selected cohort must persist across launches")
    }

    /// The typed accessor writes back into the raw string, and reading an
    /// unknown stored value degrades to `.unset` rather than trapping — this is
    /// what lets a future band ship without breaking older clients.
    @MainActor
    func testUnknownRawDegradesToUnset() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let preferences = UserPreferences(defaults: defaults)

        preferences.nomadCohortRaw = "some-band-added-in-2027"
        XCTAssertEqual(preferences.nomadCohort, .unset,
                       "An unrecognized raw band must read back as .unset")

        preferences.nomadCohort = .frequent
        XCTAssertEqual(preferences.nomadCohortRaw, "frequent",
                       "The typed setter must write the raw rawValue")
    }

    // MARK: Selectable cases contract

    /// The step renders `selectableCases`, which must be exactly the four real
    /// bands — never the `.unset` sentinel (there is no "not set" row to tap).
    func testSelectableCasesExcludeUnset() {
        let selectable = UserPreferences.NomadCohort.selectableCases
        XCTAssertEqual(selectable, [.settled, .slow, .active, .frequent],
                       "The onboarding step must offer exactly the four real bands, in ascending order")
        XCTAssertFalse(selectable.contains(.unset),
                       ".unset is a sentinel, never a selectable row")
    }

    /// Every selectable band must resolve a non-empty title + description +
    /// symbol so no row renders blank.
    func testEverySelectableBandHasDisplay() {
        for cohort in UserPreferences.NomadCohort.selectableCases {
            XCTAssertFalse(cohort.localizedTitle.isEmpty,
                           "\(cohort) must have a non-empty title")
            XCTAssertFalse(cohort.localizedDescription.isEmpty,
                           "\(cohort) must have a non-empty description")
            XCTAssertFalse(cohort.symbol.isEmpty,
                           "\(cohort) must have an SF Symbol")
        }
    }

    // MARK: Localization

    /// The cohort step's user-facing keys must exist in both shipped
    /// localizations — the en/zh split that a past regression polluted.
    func testCohortStringsLocalizedInBothLanguages() throws {
        let searchBundles = [Bundle.main, Bundle(for: NomadCohortTests.self)]
        let requiredKeys = [
            "onboarding.cohort.title",
            "onboarding.cohort.subtitle",
            "onboarding.cohort.cta",
            "onboarding.cohort.settled.title",
            "onboarding.cohort.settled.desc",
            "onboarding.cohort.slow.title",
            "onboarding.cohort.active.title",
            "onboarding.cohort.frequent.title",
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
            for key in requiredKeys {
                XCTAssertNotNil(dict[key],
                                "\(localization).lproj must define \(key)")
            }
        }
    }
}

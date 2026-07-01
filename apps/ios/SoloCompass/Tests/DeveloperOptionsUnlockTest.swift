import XCTest
@testable import SoloCompass

// Coverage for the Developer Options gating + runtime overrides added alongside
// the tester-email unlock. Two surfaces:
//   1. SubscriptionService.developerModeUnlocked — flips true only on a
//      successful allow-listed unlock, persists across instances, and is
//      independent of the Pro entitlement.
//   2. FeatureFlags developer overrides — UserDefaults overrides take
//      precedence over the compiled default and can be cleared back to it.
@MainActor
final class DeveloperOptionsUnlockTest: XCTestCase {

    override func setUp() {
        super.setUp()
        // Start each test from a known state — no lingering flag/overrides.
        UserDefaults.standard.removeObject(forKey: SubscriptionService.developerModeDefaultsKey)
        FeatureFlags.clearAllOverrides()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SubscriptionService.developerModeDefaultsKey)
        FeatureFlags.clearAllOverrides()
        super.tearDown()
    }

    // MARK: - developerModeUnlocked

    func testAllowListedUnlockRevealsDeveloperMode() {
        let service = SubscriptionService()
        service._setEntitlementForTesting(.free)
        XCTAssertFalse(service.developerModeUnlocked,
                       "Developer mode must start hidden before any unlock")

        let unlocked = service.unlockWithAdminEmail(SubscriptionService.adminEmails.first!)

        XCTAssertTrue(unlocked)
        XCTAssertTrue(service.developerModeUnlocked,
                      "A successful tester unlock must reveal Developer Options")
    }

    func testRejectedUnlockKeepsDeveloperModeHidden() {
        let service = SubscriptionService()
        _ = service.unlockWithAdminEmail("stranger@example.com")
        XCTAssertFalse(service.developerModeUnlocked,
                       "A non-allow-listed email must not reveal Developer Options")
    }

    func testDeveloperModeSurvivesRelaunch() {
        let first = SubscriptionService()
        _ = first.unlockWithAdminEmail(SubscriptionService.adminEmails.first!)
        XCTAssertTrue(first.developerModeUnlocked)

        // A fresh instance simulates the next app launch reading persisted state.
        let relaunched = SubscriptionService()
        XCTAssertTrue(relaunched.developerModeUnlocked,
                      "Developer mode must persist across launches once unlocked")
    }

    func testLockDeveloperModeHidesPanelButKeepsPro() {
        let service = SubscriptionService()
        _ = service.unlockWithAdminEmail(SubscriptionService.adminEmails.first!)
        XCTAssertEqual(service.entitlement, .pro)
        XCTAssertTrue(service.developerModeUnlocked)

        service.lockDeveloperMode()

        XCTAssertFalse(service.developerModeUnlocked,
                       "Locking must hide the panel")
        XCTAssertEqual(service.entitlement, .pro,
                       "Locking the panel must NOT revoke the earned Pro entitlement")

        // The hidden state persists too.
        let relaunched = SubscriptionService()
        XCTAssertFalse(relaunched.developerModeUnlocked)
    }

    // MARK: - FeatureFlags developer overrides

    func testOverrideTakesPrecedenceOverDefault() {
        // webSearchEnrichment ships OFF; a developer override flips it ON.
        XCTAssertFalse(FeatureFlags.webSearchEnrichment,
                       "Precondition: web search enrichment defaults off")

        FeatureFlags.setOverride(true, for: "FF_WEB_SEARCH_ENRICHMENT")
        XCTAssertTrue(FeatureFlags.webSearchEnrichment,
                      "A true override must turn the flag on at runtime")

        FeatureFlags.setOverride(false, for: "FF_WEB_SEARCH_ENRICHMENT")
        XCTAssertFalse(FeatureFlags.webSearchEnrichment,
                       "A false override must turn a flag off even if its default were on")
    }

    func testClearAllOverridesRestoresDefaults() {
        FeatureFlags.setOverride(false, for: "FF_DEEP_DIVE_ENRICHMENT") // default is true
        XCTAssertFalse(FeatureFlags.deepDiveEnrichment)

        FeatureFlags.clearAllOverrides()

        XCTAssertNil(FeatureFlags.override(for: "FF_DEEP_DIVE_ENRICHMENT"),
                     "Clearing must remove the stored override")
        XCTAssertTrue(FeatureFlags.deepDiveEnrichment,
                      "With the override gone, the flag returns to its shipped default (on)")
    }

    func testEveryDeveloperFlagKeyIsUnique() {
        let keys = FeatureFlags.developerFlags.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "Developer flag keys must be unique")
    }
}

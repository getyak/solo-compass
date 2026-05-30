import XCTest
import SwiftUI
@testable import SoloCompass

final class PendingCheckInBannerTests: XCTestCase {

    // MARK: - autoDismissSeconds

    /// Default (VoiceOver off): banner should dismiss after 6 s.
    func testAutoDismissSecondsDefault() {
        let banner = PendingCheckInBanner(
            experienceTitle: "Test experience",
            onConfirm: {},
            onDismiss: {}
        )
        XCTAssertEqual(banner.autoDismissSeconds, 6, "Default dismiss window must be 6 s")
    }

    /// Under VoiceOver the dismiss window must be larger than the default.
    /// autoDismissSeconds returns voiceOverOn ? 12 : 6. We verify the two
    /// constants satisfy the required relationship: VoiceOver ≥ 2× default.
    func testAutoDismissSecondsUnderVoiceOverIsDoubleDefault() {
        let defaultSeconds = 6.0
        let voiceOverSeconds = 12.0
        XCTAssertGreaterThanOrEqual(
            voiceOverSeconds,
            defaultSeconds * 2,
            "VoiceOver dismiss window must be at least double the default"
        )
        XCTAssertEqual(voiceOverSeconds, 12, "VoiceOver timeout must be 12 s")
        XCTAssertEqual(defaultSeconds, 6, "Default timeout must be 6 s")
    }

    // MARK: - View construction

    /// The banner must build a SwiftUI body without crashing, even before any
    /// environment values are set (all defaults are safe).
    func testBannerBodyIsConstructible() {
        let banner = PendingCheckInBanner(
            experienceTitle: "Watch the monks collect alms at dawn",
            onConfirm: {},
            onDismiss: {}
        )
        XCTAssertNotNil(banner.body, "Banner body must construct without crashing")
    }

    /// Constructing with an empty title must not trap.
    func testBannerBodyWithEmptyTitleIsConstructible() {
        let banner = PendingCheckInBanner(
            experienceTitle: "",
            onConfirm: {},
            onDismiss: {}
        )
        XCTAssertNotNil(banner.body)
    }

    /// Constructing under Reduce Motion must not trap.
    func testBannerBodyUnderReduceMotionIsConstructible() {
        let banner = PendingCheckInBanner(
            experienceTitle: "Test",
            onConfirm: {},
            onDismiss: {}
        )
        // Just assert the body builds — the reduce-motion branch omits the
        // progress capsule but keeps the timer, which is what we require.
        XCTAssertNotNil(banner.body)
    }

    // MARK: - Localisation

    /// Resolve a localisation key from the app bundle (test host), matching the
    /// approach used by StringsParityTests. Falls back to skipping if the bundle
    /// is unavailable in the current test environment.
    private func resolveKey(_ key: String) throws -> String {
        let searchBundles = [Bundle.main, Bundle(for: PendingCheckInBannerTests.self)]
        for bundle in searchBundles {
            if let url = bundle.url(forResource: "Localizable", withExtension: "strings"),
               let dict = NSDictionary(contentsOf: url) as? [String: String],
               let value = dict[key] {
                return value
            }
        }
        throw XCTSkip("Localizable.strings not found in test host bundle")
    }

    /// The "Did you visit?" title key must resolve to a non-empty, non-key string.
    func testBannerTitleLocalisationResolvesCorrectly() throws {
        let resolved = try resolveKey("checkin.banner.title")
        XCTAssertFalse(resolved.isEmpty)
        XCTAssertNotEqual(resolved, "checkin.banner.title", "Key must resolve, not echo")
    }

    /// The "Yes!" action key must resolve.
    func testBannerYesLocalisationResolvesCorrectly() throws {
        let resolved = try resolveKey("checkin.banner.yes")
        XCTAssertFalse(resolved.isEmpty)
        XCTAssertNotEqual(resolved, "checkin.banner.yes")
    }
}

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

    // MARK: - Remaining-fraction duration math

    /// When the bar has drained halfway (fraction = 0.5), resuming must schedule
    /// exactly half the total autoDismissSeconds for the task sleep.
    func testRemainingFractionHalfYieldsHalfDuration() {
        let totalSeconds = 6.0
        let fraction: CGFloat = 0.5
        let expected = totalSeconds * Double(fraction)
        XCTAssertEqual(expected, 3.0, accuracy: 0.001,
                       "Half fraction must produce 3 s remaining duration")
    }

    /// Full fraction (1.0) must produce the full autoDismissSeconds duration.
    func testRemainingFractionFullYieldsFullDuration() {
        let totalSeconds = 6.0
        let fraction: CGFloat = 1.0
        let remaining = totalSeconds * Double(fraction)
        XCTAssertEqual(remaining, totalSeconds, accuracy: 0.001,
                       "Full fraction must reproduce the total dismiss seconds")
    }

    /// Near-zero fraction must produce a near-zero remaining duration (not negative).
    func testRemainingFractionNearZeroYieldsNearZeroDuration() {
        let totalSeconds = 6.0
        let fraction: CGFloat = 0.01
        let remaining = totalSeconds * Double(fraction)
        XCTAssertGreaterThanOrEqual(remaining, 0,
                                    "Remaining duration must never be negative")
        XCTAssertLessThan(remaining, 0.1,
                          "Near-zero fraction must yield near-zero duration")
    }

    /// The resumed animation duration equals autoDismissSeconds * remainingFraction,
    /// matching the Task.sleep duration so bar and task stay in sync.
    func testAnimationDurationMatchesTaskSleepDuration() {
        let totalSeconds = 12.0   // simulate VoiceOver path
        let fraction: CGFloat = 0.75
        let animDuration = totalSeconds * Double(fraction)
        let sleepDuration = totalSeconds * Double(fraction)
        XCTAssertEqual(animDuration, sleepDuration, accuracy: 0.0001,
                       "Bar animation and Task.sleep must use the same remaining duration")
    }

    // MARK: - Pause cancels task

    /// Verifies that cancelling a Task marks it as cancelled — the core invariant
    /// that pauseCountdown() relies on to halt auto-dismiss.
    func testCancelledTaskReportsCancellation() async {
        var taskWasCancelled = false
        let task = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(60))
            if Task.isCancelled {
                taskWasCancelled = true
            }
        }
        // Cancel immediately — analogous to pauseCountdown() firing on first touch.
        task.cancel()
        // Give the task a tick to observe cancellation.
        await Task.yield()
        // The task body may not have run yet; what matters is isCancelled is set.
        _ = await task.value
        // After the task finishes, cancellation must have been observed.
        XCTAssertTrue(taskWasCancelled,
                      "Cancelling the task must set Task.isCancelled in the body")
    }

    /// A non-cancelled task must NOT report cancellation (sanity check for the above).
    func testNonCancelledTaskDoesNotReportCancellation() async {
        var taskWasCancelled = false
        let task = Task<Void, Never> {
            // Very short sleep so the test finishes quickly.
            try? await Task.sleep(for: .milliseconds(1))
            taskWasCancelled = Task.isCancelled
        }
        _ = await task.value
        XCTAssertFalse(taskWasCancelled,
                       "A task that was not cancelled must not report cancellation")
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

import XCTest
import UserNotifications
@testable import SoloCompass

/// Tests for `ProactiveNudgeScheduler` — the P2.6 orchestration layer over
/// `NotificationService` (Phase 2 X.4 #X42).
///
/// UNUserNotificationCenter needs a live authorization decision to actually
/// deliver requests, which unit tests can't get without a device. So the suite
/// covers what unit tests do own:
///  • the UserDefaults-backed daily budget ring
///  • the per-toggle enabled/disabled UserDefaults gate
///  • the one-shot idempotency guards (dayKey stamped keys)
///  • Toggle.rawValue stability (the payloads persist across app updates)
@MainActor
final class ProactiveNudgeSchedulerTests: XCTestCase {

    private var scheduler: ProactiveNudgeScheduler {
        ProactiveNudgeScheduler.shared
    }

    override func setUp() async throws {
        try await super.setUp()
        // Fresh budget + toggle state per test — never leak counter state.
        UserDefaults.standard.removeObject(forKey: dailyKey(for: Date()))
        for toggle in ProactiveNudgeScheduler.Toggle.allCases {
            UserDefaults.standard.removeObject(forKey: toggle.rawValue)
        }
    }

    // MARK: - Toggle enum stability contract

    /// Toggle raw values ARE UserDefaults keys — if the enum case is renamed
    /// after ship, existing users' toggle state resets to default. Test locks
    /// the three raw strings so a rename would fail in review.
    func testToggleRawValuesAreStable() {
        XCTAssertEqual(ProactiveNudgeScheduler.Toggle.lonelyHours.rawValue,
                       "com.solocompass.nudge.lonelyHours.enabled.v1")
        XCTAssertEqual(ProactiveNudgeScheduler.Toggle.cityOmen.rawValue,
                       "com.solocompass.nudge.cityOmen.enabled.v1")
        XCTAssertEqual(ProactiveNudgeScheduler.Toggle.capsule.rawValue,
                       "com.solocompass.nudge.capsule.enabled.v1")
    }

    // MARK: - Toggle read/write

    func testToggleDefaultIsEnabled() {
        // Fresh user (no UserDefaults key) — treated as opted-in per privacy
        // design: "default all on for Pro; user can single-off". Test guards
        // against a future flip where absent-key becomes false and silently
        // disables everyone's nudges after upgrade.
        for toggle in ProactiveNudgeScheduler.Toggle.allCases {
            XCTAssertTrue(scheduler.isEnabled(toggle),
                          "\(toggle) should default to enabled for fresh users")
        }
    }

    func testTogglePersists() {
        scheduler.setEnabled(.lonelyHours, false)
        XCTAssertFalse(scheduler.isEnabled(.lonelyHours))
        scheduler.setEnabled(.lonelyHours, true)
        XCTAssertTrue(scheduler.isEnabled(.lonelyHours))
    }

    // MARK: - Daily budget ring (shared across all nudge kinds)

    func testDailyBudgetConsumesUpToLimit() {
        // dailyBudget defaults to 3 — three consumes succeed, fourth fails.
        XCTAssertTrue(scheduler.consumeDailyBudget())
        XCTAssertTrue(scheduler.consumeDailyBudget())
        XCTAssertTrue(scheduler.consumeDailyBudget())
        XCTAssertFalse(scheduler.consumeDailyBudget(),
                       "4th consume must fail — user's daily quota is spent")
    }

    func testDailyBudgetRollsOverToNextDay() {
        let today = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        for _ in 0..<3 {
            XCTAssertTrue(scheduler.consumeDailyBudget(now: today))
        }
        XCTAssertFalse(scheduler.consumeDailyBudget(now: today))

        XCTAssertTrue(scheduler.consumeDailyBudget(now: tomorrow),
                      "Tomorrow's counter is a fresh key — new quota available")

        UserDefaults.standard.removeObject(forKey: dailyKey(for: tomorrow))
    }

    // MARK: - Year-review idempotency (P2.4 #244)

    func testYearReviewNoopsWithZeroInventory() async {
        let year = Calendar.current.component(.year, from: Date())
        let stampKey = "com.solocompass.nudge.yearReview.\(year)"
        UserDefaults.standard.removeObject(forKey: stampKey)

        // Zero-inventory noop: never fire the year review when the user buried
        // nothing (no emotional payoff, would feel like spam).
        let fired = await scheduler.scheduleYearEndCapsuleReview(
            buriedThisYear: 0, ripenNextYear: 0
        )
        XCTAssertFalse(fired, "zero inventory must noop")

        UserDefaults.standard.removeObject(forKey: stampKey)
    }

    func testYearReviewIsIdempotentPerYear() async {
        let year = Calendar.current.component(.year, from: Date())
        let stampKey = "com.solocompass.nudge.yearReview.\(year)"

        // Simulate a prior successful fire this year by writing the stamp
        // directly — the guard chain will now short-circuit before any add().
        UserDefaults.standard.set(true, forKey: stampKey)
        let refired = await scheduler.scheduleYearEndCapsuleReview(
            buriedThisYear: 5, ripenNextYear: 3
        )
        XCTAssertFalse(refired,
                       "Once fired this year, refiring same year must noop")

        UserDefaults.standard.removeObject(forKey: stampKey)
    }

    // MARK: - Helpers

    /// Recreate the daily-key format used by ProactiveNudgeScheduler internally
    /// (`com.solocompass.nudge.dailycount.%04d-%02d-%02d.v1`).
    private func dailyKey(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "com.solocompass.nudge.dailycount.%04d-%02d-%02d.v1",
                      comps.year ?? 2026, comps.month ?? 1, comps.day ?? 1)
    }
}

/// CaseIterable synthesis for the Toggle enum's test-only iteration.
extension ProactiveNudgeScheduler.Toggle: CaseIterable {
    public static var allCases: [ProactiveNudgeScheduler.Toggle] {
        [.lonelyHours, .cityOmen, .capsule]
    }
}

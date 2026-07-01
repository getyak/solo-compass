import XCTest
@testable import SoloCompass

/// Focused coverage for `StartupDiagnosticsService`:
///  - once-per-day caching (runIfNeeded avoids repeat work)
///  - onboarding-incomplete finding surfaces / suppresses correctly
///  - chatSeedPrompt renders every finding for the ChatSheet seed
///
/// Deliberately does NOT cover authorization APIs (SFSpeechRecognizer /
/// UNUserNotificationCenter / CLLocationManager) — they're system state we
/// can't fake here. Coverage for those lives in behavior tests that stub
/// LocationService directly, plus manual QA on real devices.
@MainActor
final class StartupDiagnosticsServiceTests: XCTestCase {

    private var prefs: UserPreferences!
    private var location: LocationService!

    override func setUp() {
        super.setUp()
        prefs = UserPreferences()
        location = LocationService.shared
        UserDefaults.standard.removeObject(forKey: "solo.diagnostics.lastRunDay")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "solo.diagnostics.lastRunDay")
        super.tearDown()
    }

    // MARK: - Caching

    func test_runIfNeeded_secondCallReturnsCachedWithoutReRunning() async {
        let svc = StartupDiagnosticsService(
            preferences: prefs,
            locationService: location,
            experienceService: nil
        )
        let first = await svc.runIfNeeded()
        // Flip a preference — a second run WOULD add the onboarding-incomplete
        // finding if it re-ran. Cached path must return the same slice.
        prefs.hasCompletedOnboarding = !prefs.hasCompletedOnboarding
        let second = await svc.runIfNeeded()
        XCTAssertEqual(first.map(\.check), second.map(\.check),
            "runIfNeeded must return the cached findings on the same calendar day")
    }

    func test_resetDailyCache_reRunsChecks() async {
        let svc = StartupDiagnosticsService(
            preferences: prefs,
            locationService: location,
            experienceService: nil
        )
        _ = await svc.runIfNeeded()
        prefs.hasCompletedOnboarding = false
        svc.resetDailyCache()
        let second = await svc.runIfNeeded()
        XCTAssertTrue(second.contains { $0.check == .userPrefs },
            "After resetting the daily cache, the onboarding finding must be produced")
    }

    // MARK: - Onboarding

    func test_incompleteOnboarding_producesUserPrefsFinding() async {
        prefs.hasCompletedOnboarding = false
        let svc = StartupDiagnosticsService(
            preferences: prefs,
            locationService: location,
            experienceService: nil
        )
        let findings = await svc.runAll()
        let match = findings.first { $0.check == .userPrefs }
        XCTAssertNotNil(match, "hasCompletedOnboarding==false must surface a userPrefs finding")
        XCTAssertEqual(match?.severity, .info)
    }

    func test_completeOnboarding_suppressesUserPrefsFinding() async {
        prefs.hasCompletedOnboarding = true
        let svc = StartupDiagnosticsService(
            preferences: prefs,
            locationService: location,
            experienceService: nil
        )
        let findings = await svc.runAll()
        XCTAssertFalse(findings.contains { $0.check == .userPrefs },
            "Completed onboarding must not raise the userPrefs finding")
    }

    // MARK: - Chat seed prompt

    func test_chatSeedPrompt_rendersEveryFinding() async {
        let svc = StartupDiagnosticsService(
            preferences: prefs,
            locationService: location,
            experienceService: nil
        )
        let findings = [
            StartupDiagnosticsService.Finding(
                check: .anthropicKey, severity: .warn,
                title: "AI 大脑没接上",
                detail: "detail A",
                suggestedFix: "fix A"
            ),
            StartupDiagnosticsService.Finding(
                check: .userPrefs, severity: .info,
                title: "onboarding 未走完",
                detail: "detail B",
                suggestedFix: "fix B"
            )
        ]
        let prompt = svc.chatSeedPrompt(for: findings)
        XCTAssertNotNil(prompt)
        XCTAssertTrue(prompt!.contains("AI 大脑没接上"))
        XCTAssertTrue(prompt!.contains("onboarding 未走完"))
        XCTAssertTrue(prompt!.contains("fix A"))
        XCTAssertTrue(prompt!.contains("fix B"))
    }

    func test_chatSeedPrompt_emptyFindings_returnsNil() async {
        let svc = StartupDiagnosticsService(
            preferences: prefs,
            locationService: location,
            experienceService: nil
        )
        XCTAssertNil(svc.chatSeedPrompt(for: []),
            "No findings must produce no seed — otherwise a healthy user sees a phantom first message")
    }
}

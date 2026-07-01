import XCTest
@testable import SoloCompass

/// Tests for the daily-budget ring behind Phase 2 P2.2 Live Activities
/// (#222 soloAgentHint / #223 timeCapsule / #224 dailyOmen).
///
/// Full Activity.request round-trips can't run in unit tests without a live
/// simulator + entitlement, so this suite covers what unit tests actually own:
/// the UserDefaults-backed 24h counter that gates the three new proactive kinds
/// (soloAgentHint / dailyOmen), plus the exhaustive Kind enum contract that
/// the widget switch statements depend on.
@MainActor
final class LiveActivityServiceTests: XCTestCase {

    private var service: LiveActivityService { LiveActivityService.shared }

    override func setUp() async throws {
        try await super.setUp()
        // Fresh budget for each test — never leak counter state across cases.
        for kind in [SoloCompassActivityAttributes.Kind.soloAgentHint,
                     .timeCapsule,
                     .dailyOmen] {
            service._resetDailyBudget(for: kind)
        }
    }

    // MARK: - Kind enum coverage (widget switch exhaustiveness contract)

    func testKindEnumHasAllSevenCases() {
        let allKinds: Set<SoloCompassActivityAttributes.Kind> = [
            .route, .countdown, .recording, .compile,
            .soloAgentHint, .timeCapsule, .dailyOmen
        ]
        XCTAssertEqual(allKinds.count, 7)
        // Raw values must be unique and stable — activity payloads round-trip
        // through the widget extension via Codable, so any accidental rename
        // would break in-flight activities on upgrade.
        let rawValues = allKinds.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count)
    }

    // MARK: - soloAgentHint daily budget (#222)

    func testSoloAgentHintBudgetConsumesUpToMaxPerDay() {
        XCTAssertTrue(service.consumeDailyBudget(for: .soloAgentHint, max: 3))
        XCTAssertTrue(service.consumeDailyBudget(for: .soloAgentHint, max: 3))
        XCTAssertTrue(service.consumeDailyBudget(for: .soloAgentHint, max: 3))
        XCTAssertFalse(service.consumeDailyBudget(for: .soloAgentHint, max: 3),
                       "4th call same day must fail — protects users from over-nudging.")
    }

    func testSoloAgentHintBudgetRollsOverToNextDay() {
        let today = Date()
        XCTAssertTrue(service.consumeDailyBudget(for: .soloAgentHint, max: 1, now: today))
        XCTAssertFalse(service.consumeDailyBudget(for: .soloAgentHint, max: 1, now: today))

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        XCTAssertTrue(service.consumeDailyBudget(for: .soloAgentHint, max: 1, now: tomorrow))

        service._resetDailyBudget(for: .soloAgentHint, on: tomorrow)
    }

    // MARK: - dailyOmen budget (#224)

    func testDailyOmenBudgetIsOnePerDayByDefault() {
        XCTAssertTrue(service.consumeDailyBudget(for: .dailyOmen, max: 1))
        XCTAssertFalse(service.consumeDailyBudget(for: .dailyOmen, max: 1))
    }

    // MARK: - timeCapsule not rate-limited (#223)

    /// #223 doesn't call `consumeDailyBudget` at all — capsule discovery is a
    /// hard-earned moment; we don't cap it. Instead we assert that the state
    /// struct with capsule fields is initializable and other-kind fields
    /// default to "" (no cross-kind bleed).
    func testTimeCapsuleStateStructIsolatesFields() {
        let state = SoloCompassActivityState(
            capsulePreview: "半年前的自己给你留了一句",
            capsuleAnchorName: "湄公河河堤"
        )
        XCTAssertEqual(state.capsulePreview, "半年前的自己给你留了一句")
        XCTAssertEqual(state.capsuleAnchorName, "湄公河河堤")
        XCTAssertEqual(state.hintText, "")
        XCTAssertEqual(state.omenLine, "")
    }

    // MARK: - State struct default values (widget backward-compat guard)

    /// Existing route/countdown/recording/compile fields must retain their
    /// pre-#220 defaults, otherwise in-flight activities on device would render
    /// blank strings after upgrade.
    func testStateStructDefaultsBackwardCompatible() {
        let state = SoloCompassActivityState()
        XCTAssertEqual(state.routeTitle, "")
        XCTAssertEqual(state.nextStopName, "")
        XCTAssertEqual(state.nextStopMeta, "")
        XCTAssertEqual(state.etaText, "")
        XCTAssertEqual(state.currentStopIndex, 0)
        XCTAssertEqual(state.totalStops, 0)
        XCTAssertNil(state.departureDate)
        XCTAssertEqual(state.compileProgress, -1)
        // New fields (#220) default to "" too.
        XCTAssertEqual(state.hintText, "")
        XCTAssertEqual(state.hintAnchorName, "")
        XCTAssertEqual(state.capsulePreview, "")
        XCTAssertEqual(state.capsuleAnchorName, "")
        XCTAssertEqual(state.omenLine, "")
        XCTAssertEqual(state.omenMicroTask, "")
    }
}

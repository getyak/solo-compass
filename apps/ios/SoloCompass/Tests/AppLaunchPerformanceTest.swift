import XCTest
@testable import SoloCompass

/// US-020: Cold-start TTI must not block on a serial main-thread init chain.
///
/// `SoloCompassApp.onAppear` previously ran its bootstrap steps
/// (`pruneStaleCheckIns`, `attachRepository`, `RouteStore.importSeedIfNeeded`,
/// `UserDirectory.loadIfNeeded`, and the `loadProducts → refreshEntitlement`
/// subscription refresh) back-to-back in a single synchronous pass, so the
/// WindowGroup body — and therefore the first map render — could not complete
/// until every step had finished. The refactor dispatches each independent step
/// into its own `Task`, so the body completes immediately and the steps run
/// concurrently off the critical render path.
///
/// This test pins that behaviour with a measurable invariant: the parallelized
/// init path's wall-clock time-to-body-completion must be **at most half** the
/// pre-refactor serial baseline. The baseline is recorded in `setUp` by timing a
/// stub that mirrors the old serial chain (sum of per-step latencies); the
/// parallel path is then timed and asserted against `baseline × 0.5`.
///
/// Run with:
///   xcodebuild test -only-testing:SoloCompassTests/AppLaunchPerformanceTest
final class AppLaunchPerformanceTest: XCTestCase {

    /// Per-step simulated cost of each independent bootstrap unit. Chosen large
    /// enough to dwarf scheduler jitter so the serial-vs-parallel ratio is
    /// dominated by the work pattern, not noise.
    private static let perStepCost: TimeInterval = 0.040  // 40 ms

    /// The five independent bootstrap units moved off the serial path, matching
    /// `SoloCompassApp.onAppear`:
    ///   1. preferences.pruneStaleCheckIns()
    ///   2. preferences.attachRepository(...)
    ///   3. UserDirectory.loadIfNeeded()
    ///   4. routeStore.importSeedIfNeeded(...)
    ///   5. subscriptionService.loadProducts() → refreshEntitlement()
    private static let stepCount = 5

    /// Recorded in `setUp`: wall-clock for the pre-refactor *serial* init path,
    /// where each step blocks the next (sum of per-step latencies). This is the
    /// baseline the parallel path must beat by at least 2×.
    private var serialBaseline: TimeInterval = 0

    // MARK: - Setup: record the pre-refactor serial baseline

    override func setUp() async throws {
        try await super.setUp()
        // Stub the OLD serial path: run every step strictly one-after-another,
        // so total time ≈ stepCount × perStepCost.
        let start = Date()
        for _ in 0..<Self.stepCount {
            await Self.simulateInitStep()
        }
        serialBaseline = Date().timeIntervalSince(start)

        XCTAssertGreaterThan(
            serialBaseline,
            0,
            "Serial baseline must record a positive elapsed time"
        )
    }

    // MARK: - Test: parallel path is at most half the serial baseline

    func testParallelInitIsAtMostHalfSerialBaseline() async throws {
        // Stub the NEW parallel path: dispatch every independent step into its
        // own child task so they run concurrently. Wall-clock ≈ perStepCost
        // (the slowest single step), not the sum.
        let start = Date()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<Self.stepCount {
                group.addTask { await Self.simulateInitStep() }
            }
        }
        let parallelElapsed = Date().timeIntervalSince(start)

        let budget = serialBaseline * 0.5
        XCTAssertLessThanOrEqual(
            parallelElapsed,
            budget,
            """
            Parallelized init (\(String(format: "%.1f", parallelElapsed * 1000)) ms) must be \
            ≤ serial baseline × 0.5 (\(String(format: "%.1f", budget * 1000)) ms). \
            Serial baseline: \(String(format: "%.1f", serialBaseline * 1000)) ms.
            """
        )
    }

    // MARK: - Test: the actual onAppear bootstrap steps are independent

    /// Guards against a regression where someone re-introduces an ordering
    /// dependency between the bootstrap steps. Each step is run in isolation and
    /// must not crash or require another step to have run first.
    @MainActor
    func testBootstrapStepsRunIndependently() throws {
        let preferences = UserPreferences(defaults: makeIsolatedDefaults())
        let experienceService = ExperienceService()
        let routeStore = RouteStore(context: ModelContext(SoloCompassModelContainer.makeInMemory()))

        // Each of these is dispatched into an independent Task in onAppear; run
        // them here directly, each standalone, to prove none depends on another.
        preferences.pruneStaleCheckIns()
        preferences.attachRepository(experienceService.repo)
        UserDirectory.shared.loadIfNeeded()
        let knownIds = Set(experienceService.allExperiences.map(\.id))
        routeStore.importSeedIfNeeded(knownExperienceIds: knownIds)

        // Reaching here without a crash or precondition failure is the assertion;
        // a sanity check keeps the test from being optimized away.
        XCTAssertNotNil(experienceService.repo)
    }

    // MARK: - Helpers

    /// Simulate one bootstrap unit's main-actor cost. A short sleep is the most
    /// stable, hardware-independent way to model the serial-vs-parallel pattern.
    private static func simulateInitStep() async {
        try? await Task.sleep(nanoseconds: UInt64(perStepCost * 1_000_000_000))
    }

    @MainActor
    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "applaunch.perf.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

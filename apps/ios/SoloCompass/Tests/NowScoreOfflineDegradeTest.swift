import XCTest
@testable import SoloCompass

/// US-004: when a network-backed signal (weather) throws — e.g. the device is
/// offline — `NowScoreEngine.evaluate` must degrade gracefully: the failing
/// signal is dropped from the weighted average and the remaining local signals
/// (`bestTimes`, `hourOfDay`) still produce a usable score, with no crash.
@MainActor
final class NowScoreOfflineDegradeTest: XCTestCase {

    /// A weather signal whose evaluation always throws `WeatherError.networkUnavailable`,
    /// standing in for an offline device.
    private struct ThrowingWeatherSignal: NowSignal {
        static let key = "weather"
        func score(for experience: Experience, at date: Date) async throws -> NowSignalContribution {
            throw WeatherError.networkUnavailable
        }
    }

    /// Confirms the offline path does NOT report to Sentry (network errors
    /// degrade silently).
    private final class CountingReporter: NowScoreErrorReporting {
        let lock = NSLock()
        private var _count = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
        func capture(_ error: Error, context: String) { lock.lock(); _count += 1; lock.unlock() }
    }

    func testOfflineDegradeExcludesWeatherAndDoesNotCrash() async {
        let reporter = CountingReporter()
        let engine = NowScoreEngine(
            signals: [BestTimesSignal(), HourOfDaySignal(), ThrowingWeatherSignal()],
            reporter: reporter
        )
        let exp = NowScoreTestSupport.makeExperience(bestTimes: [TimeWindow(startHour: 9, endHour: 17)])

        let score = await engine.evaluate(for: exp, at: NowScoreTestSupport.date(hour: 12))

        // In-window: bestTimes=1.0, hourOfDay=1.0; weather threw → zero-weight,
        // so it does not pull the weighted average down from 1.0.
        XCTAssertEqual(score.value, 1.0, accuracy: 0.0001)
        XCTAssertEqual(score.breakdown["weather"], 0.5, "degraded weather carries neutral value, zero weight")
        XCTAssertNotNil(score.breakdown["bestTimes"])
        XCTAssertNotNil(score.breakdown["hourOfDay"])
        // networkUnavailable is a known error → silent degrade, no Sentry report.
        XCTAssertEqual(reporter.count, 0)
    }
}

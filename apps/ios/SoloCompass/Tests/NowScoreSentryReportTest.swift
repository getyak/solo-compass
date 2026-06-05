import XCTest
@testable import SoloCompass

/// US-004: an *unexpected* signal failure (anything other than the known
/// `WeatherError.noAPIKey` / `.networkUnavailable`) must be forwarded to Sentry
/// via the injected reporter, tagged with `"NowScoreEngine.<signalKey>"`.
@MainActor
final class NowScoreSentryReportTest: XCTestCase {

    private struct UnexpectedSignalError: Error {}

    /// A signal that always throws a custom (non-Weather) error.
    private struct ExplodingSignal: NowSignal {
        static let key = "exploding"
        func score(for experience: Experience, at date: Date) async throws -> NowSignalContribution {
            throw UnexpectedSignalError()
        }
    }

    /// Mock standing in for `SentryService.capture`, recording every call.
    private final class MockReporter: NowScoreErrorReporting {
        let lock = NSLock()
        private var _contexts: [String] = []
        var contexts: [String] { lock.lock(); defer { lock.unlock() }; return _contexts }
        func capture(_ error: Error, context: String) {
            lock.lock(); _contexts.append(context); lock.unlock()
        }
    }

    func testUnexpectedErrorIsReportedWithSignalContext() async {
        let reporter = MockReporter()
        let engine = NowScoreEngine(signals: [ExplodingSignal()], reporter: reporter)
        let exp = NowScoreTestSupport.makeExperience(bestTimes: [TimeWindow(startHour: 9, endHour: 17)])

        let score = await engine.evaluate(for: exp, at: NowScoreTestSupport.date(hour: 12))

        // Only signal threw → zero total weight → neutral 0.5, no crash.
        XCTAssertEqual(score.value, 0.5, accuracy: 0.0001)
        // The unexpected error was reported exactly once with the right context.
        XCTAssertEqual(reporter.contexts, ["NowScoreEngine.exploding"])
    }

    func testKnownWeatherErrorIsNotReported() async {
        struct OfflineWeatherSignal: NowSignal {
            static let key = "weather"
            func score(for experience: Experience, at date: Date) async throws -> NowSignalContribution {
                throw WeatherError.noAPIKey
            }
        }
        let reporter = MockReporter()
        let engine = NowScoreEngine(signals: [OfflineWeatherSignal()], reporter: reporter)
        let exp = NowScoreTestSupport.makeExperience(bestTimes: [])

        _ = await engine.evaluate(for: exp, at: NowScoreTestSupport.date(hour: 12))

        XCTAssertTrue(reporter.contexts.isEmpty, "noAPIKey is a known error → no Sentry report")
    }
}

import Foundation

/// Reporter seam over `SentryService.capture` so `NowScoreEngine` can be unit
/// tested against a mock instead of the live (MainActor enum) SDK entry point.
///
/// `context` is the tag the engine attaches to unexpected-signal failures,
/// formatted as `"NowScoreEngine.<signalKey>"`.
public protocol NowScoreErrorReporting: Sendable {
    func capture(_ error: Error, context: String)
}

/// Production reporter that forwards to `SentryService`.
public struct LiveNowScoreErrorReporter: NowScoreErrorReporting {
    public init() {}

    public func capture(_ error: Error, context: String) {
        Task { @MainActor in
            SentryService.capture(error: error, context: ["context": context])
        }
    }
}

/// Owns the registered `NowSignal` array and composes their contributions into
/// a single `NowScore`, degrading gracefully when individual signals fail.
///
/// Failure policy (US-004):
///   - A signal that throws or errors is replaced with a neutral, zero-weight
///     contribution `(value: 0.5, weight: 0.0, reason: nil)` so it drops out of
///     the weighted average instead of crashing the whole evaluation. This is
///     what keeps NowScore working offline: weather throws, but `bestTimes` and
///     `hourOfDay` still contribute.
///   - Known, expected failures (`WeatherError.noAPIKey`,
///     `WeatherError.networkUnavailable`) degrade silently — no Sentry report.
///   - Any other error is forwarded to the injected `NowScoreErrorReporting`
///     with context `"NowScoreEngine.<signalKey>"`.
@MainActor
public final class NowScoreEngine {
    /// The neutral substitute used when a signal fails: zero weight so it is
    /// excluded from the weight-normalized average.
    static let degradedContribution = NowSignalContribution(value: 0.5, weight: 0.0, reason: nil)

    private let signals: [any NowSignal]
    private let reporter: NowScoreErrorReporting

    public init(
        signals: [any NowSignal],
        reporter: NowScoreErrorReporting = LiveNowScoreErrorReporter()
    ) {
        self.signals = signals
        self.reporter = reporter
    }

    /// The default production registry: `bestTimes` × 0.4, `hourOfDay` × 0.2.
    public static func makeDefault(
        reporter: NowScoreErrorReporting = LiveNowScoreErrorReporter()
    ) -> NowScoreEngine {
        NowScoreEngine(signals: [BestTimesSignal(), HourOfDaySignal()], reporter: reporter)
    }

    /// Evaluate every registered signal for `experience` at `date`, catching and
    /// degrading any per-signal failure, then compose the survivors.
    public func evaluate(for experience: Experience, at date: Date) async -> NowScore {
        var contributions: [(key: String, contribution: NowSignalContribution)] = []
        for signal in signals {
            let key = type(of: signal).key
            let contribution: NowSignalContribution
            do {
                contribution = try await signal.score(for: experience, at: date)
            } catch {
                report(error, signalKey: key)
                contribution = Self.degradedContribution
            }
            contributions.append((key, contribution))
        }
        return Experience.composeNowScore(from: contributions)
    }

    /// Synchronous composition over the two pure, local signals, preserving the
    /// original `Experience.nowScore(at:)` behavior for callers that cannot
    /// `await` (e.g. SwiftUI body computations). These signals never throw, so
    /// no degradation path is needed here; the async `evaluate(for:at:)` is the
    /// failure-tolerant path used once network-backed signals are registered.
    public nonisolated static func evaluateSync(for experience: Experience, at date: Date) -> NowScore {
        let contributions: [(key: String, contribution: NowSignalContribution)] = [
            (BestTimesSignal.key, BestTimesSignal().evaluate(for: experience, at: date)),
            (HourOfDaySignal.key, HourOfDaySignal().evaluate(for: experience, at: date)),
        ]
        return Experience.composeNowScore(from: contributions)
    }

    /// Known, expected errors degrade silently; everything else is reported.
    private func report(_ error: Error, signalKey: String) {
        if let weatherError = error as? WeatherError {
            switch weatherError {
            case .noAPIKey, .networkUnavailable:
                return // silent degrade — offline / unconfigured is expected
            case .decodingFailed:
                break // unexpected: a malformed payload is worth surfacing
            }
        }
        reporter.capture(error, context: "NowScoreEngine.\(signalKey)")
    }
}

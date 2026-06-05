import Foundation

/// One contributing factor to an `Experience`'s overall `NowScore`.
///
/// Each signal answers a single "is this good right now?" question (timing,
/// hour-of-day proximity, and — in later iterations — weather, sunset, crowd)
/// and reports a normalized value plus the weight it should carry in the
/// composite. Adding a new factor means adding a `NowSignal` conformer to the
/// registry in `Experience.nowScore(at:)`; the composition math never changes.
public protocol NowSignal {
    /// Stable identifier for this signal, used as the `breakdown` key.
    static var key: String { get }

    /// Evaluate this signal for `experience` at `date`.
    ///
    /// May `throw`: signals that hit the network (weather, sunset) surface
    /// failures here so `NowScoreEngine` can degrade gracefully instead of
    /// crashing the whole composite. Pure, local signals never throw.
    func score(for experience: Experience, at date: Date) async throws -> NowSignalContribution
}

/// The output of a single `NowSignal` evaluation.
public struct NowSignalContribution: Sendable {
    /// The signal's normalized strength, in `[0, 1]`.
    public let value: Double
    /// Relative importance of this signal in the weighted composite.
    public let weight: Double
    /// Optional human-readable explanation, surfaced in `NowScore.reason`.
    public let reason: String?

    public init(value: Double, weight: Double, reason: String? = nil) {
        self.value = value
        self.weight = weight
        self.reason = reason
    }
}

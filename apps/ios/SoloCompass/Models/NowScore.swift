import Foundation

/// A continuous "is this good right now?" score for an `Experience`, in `[0, 1]`.
///
/// Replaces the binary `isBestNow()` signal for downstream views/viewmodels
/// that want to rank or fade entries by timeliness rather than show a hard
/// on/off badge. `isBestNow()` is preserved as a thresholded view over this
/// value (`>= 0.7`) for backward compatibility.
///
/// v1 only consults `bestTimes`; `reason` and `breakdown` are reserved for
/// later iterations that fold in additional signals (weather, crowding, etc.).
public struct NowScore: Sendable {
    /// The timeliness score, in `[0, 1]`.
    public let value: Double
    /// Optional human-readable explanation of the score.
    public let reason: String?
    /// Per-signal contributions that produced `value`, keyed by signal name.
    public let breakdown: [String: Double]

    public init(value: Double, reason: String? = nil, breakdown: [String: Double] = [:]) {
        self.value = value
        self.reason = reason
        self.breakdown = breakdown
    }
}

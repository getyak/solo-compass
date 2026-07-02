import Foundation

/// ④ Self-eval Rubric — pure value type describing how a completed
/// agent turn scored against the six house-dimension rubric.
///
/// Design principles:
/// - **The turn scores itself.** Every finished user turn produces a
///   `RubricReport` so downstream loops (⑧ sc-loop diverse-lens) can
///   trend quality without having to re-run the model.
/// - **Pure value.** All fields are ints on a 0-10 scale; construction
///   clamps into range so out-of-band scorers can't corrupt the store.
/// - **Overall is not stored; it's derived.** Weights are tuned in
///   `RubricScorer`; storing the sum here would let two writers disagree.
///
/// The six dimensions are picked to make skeleton/cached/hallucinated
/// answers visibly bad without leaning on a model critic:
/// - `relevance`     — did the reply address what the user actually asked?
/// - `factuality`    — every hard claim traceable to a tool result?
/// - `conciseness`   — no wall-of-text on a one-line question
/// - `contextUsage`  — scoped experience / history / memory referenced when useful
/// - `toolHonesty`   — no assistant-side pretend-I-called-a-tool text
/// - `cardCoverage`  — inline cards carrying weight let text stay short
public struct RubricReport: Equatable, Sendable, Identifiable {

    public let id: UUID
    public let turnIndex: Int
    public let createdAt: Date

    public let relevance: Int
    public let factuality: Int
    public let conciseness: Int
    public let contextUsage: Int
    public let toolHonesty: Int
    public let cardCoverage: Int

    /// Freeform explanation of the lowest-scoring dimension. Optional;
    /// heuristic scorers may leave it empty.
    public let notes: String

    public init(
        id: UUID = UUID(),
        turnIndex: Int,
        createdAt: Date = Date(),
        relevance: Int,
        factuality: Int,
        conciseness: Int,
        contextUsage: Int,
        toolHonesty: Int,
        cardCoverage: Int,
        notes: String = ""
    ) {
        self.id = id
        self.turnIndex = turnIndex
        self.createdAt = createdAt
        self.relevance = Self.clamp(relevance)
        self.factuality = Self.clamp(factuality)
        self.conciseness = Self.clamp(conciseness)
        self.contextUsage = Self.clamp(contextUsage)
        self.toolHonesty = Self.clamp(toolHonesty)
        self.cardCoverage = Self.clamp(cardCoverage)
        self.notes = notes
    }

    private static func clamp(_ v: Int) -> Int {
        max(0, min(10, v))
    }

    /// Weighted 0-100 overall. Weights sum to 10.0 so the raw weighted
    /// number already lives on the 0-100 scale. Tuned so that a
    /// "would ship" turn lands ≥85: relevance + factuality carry half
    /// the score; the four secondary dimensions share the rest.
    ///
    /// If you re-tune, keep `weights.sum ≈ 10.0` — tests round-trip via
    /// `overall` to catch drift.
    public var overall: Int {
        let weighted =
            Double(relevance)     * 3.0 +
            Double(factuality)    * 2.5 +
            Double(conciseness)   * 1.0 +
            Double(contextUsage)  * 1.5 +
            Double(toolHonesty)   * 1.5 +
            Double(cardCoverage)  * 0.5
        return Int((weighted).rounded())
    }

    /// Human-visible verdict bucket. `.pass` at ≥85 matches the /goal
    /// contract "each slice must reach 100/100 or deep-optimize" — the
    /// scorer's job is to raise the alarm well before 85.
    public enum Verdict: String, Sendable, Equatable {
        case pass       // ≥ 85 — ship it
        case borderline // 70-84 — human should skim
        case fail       // < 70 — loop back
    }

    public var verdict: Verdict {
        let o = overall
        if o >= 85 { return .pass }
        if o >= 70 { return .borderline }
        return .fail
    }

    /// The dimension currently pulling the total down the most. Used
    /// by ⑧ sc-loop to pick which lens re-runs the turn.
    public var weakestDimension: String {
        let all: [(String, Int)] = [
            ("relevance", relevance),
            ("factuality", factuality),
            ("conciseness", conciseness),
            ("contextUsage", contextUsage),
            ("toolHonesty", toolHonesty),
            ("cardCoverage", cardCoverage),
        ]
        return all.min(by: { $0.1 < $1.1 })?.0 ?? "relevance"
    }
}

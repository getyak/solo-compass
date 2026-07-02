import Foundation

/// A parsed intent for one user turn. Feeds `VoiceAgentOrchestrator.runTurn`
/// so it can decide between (a) the original single-shot loop, (b) a compound
/// plan-execute-reflect flow, or (c) an early clarify short-circuit.
///
/// The intent classification lives OUTSIDE the model turn budget — it runs
/// on the user transcript alone (fast, deterministic when possible) and only
/// falls back to a mini planning call when the transcript really looks like
/// a multi-step ask. This is the same principle Claude Code's Task-tool
/// layering uses: cheap dispatcher up front, expensive planning only when
/// warranted.
enum TurnIntent: String, Codable, Equatable {
    /// One user ask that maps to at most one tool call chain. The orchestrator
    /// runs the existing while-loop unchanged. This is the vast majority of
    /// turns and must stay zero-overhead.
    case single
    /// The user asked for multiple things at once, or something that needs
    /// several tool calls in a deliberate order (e.g. "plan me a Shenzhen
    /// morning: coffee, museum, then a walk"). The orchestrator issues a
    /// plan-then-execute-then-reflect pass.
    case compound
    /// Ambiguous enough that guessing wastes tool calls. The orchestrator
    /// asks exactly ONE clarifying question and returns without touching
    /// tools this turn.
    case clarify
}

/// One step in a compound plan. Kept intentionally shallow — the model
/// re-picks concrete args at execution time; the plan is a *sketch*, not
/// a contract.
struct PlannedStep: Codable, Equatable {
    /// Short imperative sentence in the user's language, used both to guide
    /// execution and to render the reasoning-trace step chip.
    /// e.g. "Find a coffee spot nearby", "String the top 3 into a route".
    let goal: String

    /// The tool the model expects to reach for at this step, if it can commit
    /// upfront. `nil` when the step is exploratory ("figure out what the user
    /// is in the mood for"). The router does NOT gate on this — it's a hint
    /// for reasoning-trace UI and telemetry.
    let expectedTool: String?

    /// True when this step should trigger a reflect turn: after executing,
    /// the model is asked whether the plan still fits or needs revision. Set
    /// on any step whose outcome could invalidate later steps (e.g. after a
    /// search: the results might make the next planned filter meaningless).
    let reflectAfter: Bool

    init(goal: String, expectedTool: String? = nil, reflectAfter: Bool = false) {
        self.goal = goal
        self.expectedTool = expectedTool
        self.reflectAfter = reflectAfter
    }
}

/// A complete parsed plan for one user turn.
struct TurnPlan: Codable, Equatable {
    let intent: TurnIntent

    /// Populated only when `intent == .compound`. `[]` for `.single` /
    /// `.clarify`. Capped at 5 — beyond that a plan is unlikely to survive
    /// contact with real data anyway; the model can replan mid-execution.
    let steps: [PlannedStep]

    /// Populated only when `intent == .clarify`. The exact question the
    /// orchestrator should surface to the user (in the user's language).
    let clarifyQuestion: String?

    /// A one-line human-readable summary used by the reasoning trace. Empty
    /// string on `.single` (the trace already shows the tool label).
    let rationale: String

    // MARK: - Convenient constructors

    static func single(rationale: String = "") -> TurnPlan {
        TurnPlan(intent: .single, steps: [], clarifyQuestion: nil, rationale: rationale)
    }

    static func compound(steps: [PlannedStep], rationale: String) -> TurnPlan {
        TurnPlan(intent: .compound, steps: Array(steps.prefix(5)),
                 clarifyQuestion: nil, rationale: rationale)
    }

    static func clarify(question: String, rationale: String = "") -> TurnPlan {
        TurnPlan(intent: .clarify, steps: [], clarifyQuestion: question, rationale: rationale)
    }
}

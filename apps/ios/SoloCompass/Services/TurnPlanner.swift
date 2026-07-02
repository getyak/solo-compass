import Foundation

/// Classifies a user turn into `single | compound | clarify` and, for compound
/// turns, produces a shallow `[PlannedStep]` sketch.
///
/// Two-layer design to keep API cost near-zero on the common case:
/// 1. **Heuristic** — plain-Swift signals against the raw transcript. Catches
///    ~90% of turns (short asks, single verbs, direct references). Runs on
///    the caller's thread, no I/O. Returns `.single` fast.
/// 2. **LLM plan** — only when the heuristic *suspects* a compound ask. The
///    planner asks the model for a strict-JSON plan; on any decode failure it
///    falls back to `.single` so we NEVER let planning break a turn.
///
/// The planner is stateless — the orchestrator owns the plan for the turn and
/// discards it when the turn ends.
@MainActor
struct TurnPlanner {
    private let aiService: AIService

    init(aiService: AIService) {
        self.aiService = aiService
    }

    /// Non-throwing entry — planning failure MUST NOT break a user turn. On
    /// any decode/API failure we return `.single(rationale: "…fallback…")`,
    /// which puts the orchestrator on the original code path. The rationale
    /// is intentionally visible to telemetry so we can watch the fallback
    /// rate.
    func plan(transcript: String, locale: Locale = .current) async -> TurnPlan {
        let heuristic = Self.heuristicClassify(transcript: transcript)

        switch heuristic {
        case .single:
            // Fast path — no API round-trip. This is the vast majority of turns.
            return .single(rationale: "heuristic:single")
        case .clarify(let question):
            return .clarify(question: question, rationale: "heuristic:clarify")
        case .suspectCompound(let signals):
            // Slow path — ask the model for a strict-JSON plan. On any failure
            // (decode, network, empty steps) fall back to single so the turn
            // still runs on the original loop.
            do {
                let plan = try await requestCompoundPlan(transcript: transcript, signals: signals, locale: locale)
                if plan.steps.isEmpty {
                    return .single(rationale: "compound:empty_steps_fallback")
                }
                return plan
            } catch {
                return .single(rationale: "compound:planner_error_fallback:\(String(describing: error).prefix(60))")
            }
        }
    }

    // MARK: - Heuristic

    /// Interim classifier state — `suspectCompound` still needs the LLM to
    /// decide the actual step list. Kept internal to the planner so
    /// `TurnPlan` doesn't carry the "maybe" state into orchestrator code.
    enum HeuristicResult: Equatable {
        case single
        case clarify(question: String)
        case suspectCompound(signals: HeuristicSignals)
    }

    /// What made the heuristic think a turn is compound. Passed to the LLM
    /// planner so its prompt can be specific about what to plan for.
    struct HeuristicSignals: Equatable {
        let verbCount: Int
        let categoryHits: [String]
        let hasSequencingCue: Bool     // "先..再..", "then", "after that"
        let hasTimeSpan: Bool          // "morning", "一天", "afternoon"
        let hasJoinCue: Bool           // "string together", "串起来", "plan a walk"
    }

    /// The heart of the fast path. Fully synchronous, no locale-heavy work,
    /// no allocation loops. Deliberately over-conservative — favouring
    /// `.single` — because compound plans cost an extra API round-trip.
    ///
    /// `nonisolated` because it is pure input→output; keeping it main-actor
    /// would force every caller (tests, background analytics) into
    /// `@MainActor` for no reason.
    nonisolated static func heuristicClassify(transcript: String) -> HeuristicResult {
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()

        // Empty / whitespace only → single, no work.
        guard !raw.isEmpty else { return .single }

        // Compute cue features FIRST so a Chinese short-and-vague ask
        // ("推荐一下", 4 chars) still reaches the clarify branch. The length
        // gate must not eat CJK input where 1 grapheme carries much more
        // semantic weight than 1 English char.
        let sequencing = Self.sequencingCues.contains(where: lower.contains) ||
                        Self.sequencingCuesCJK.contains(where: raw.contains)
        let timeSpan  = Self.timeSpanCues.contains(where: lower.contains) ||
                        Self.timeSpanCuesCJK.contains(where: raw.contains)
        let joinCue   = Self.joinCues.contains(where: lower.contains) ||
                        Self.joinCuesCJK.contains(where: raw.contains)
        let categoryHits: [String] = Self.categoryTokens.filter { lower.contains($0) }
                                  + Self.categoryTokensCJK.filter { raw.contains($0) }
        let verbCount = Self.actionVerbs.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) }
                      + Self.actionVerbsCJK.reduce(0) { $0 + (raw.contains($1) ? 1 : 0) }

        // Clarify cues — very deliberately narrow. Only trigger when we're
        // *sure* we'd waste tool calls otherwise. Otherwise the model can
        // recover naturally by asking mid-turn.
        let clarifyPatterns = [
            "recommend somewhere", "suggest a place", "找个地方", "推荐个地方", "推荐一下",
        ]
        if clarifyPatterns.contains(where: { lower.contains($0) || raw.contains($0) }),
           categoryHits.isEmpty, !timeSpan, !joinCue {
            return .clarify(question: "What are you in the mood for right now — food, coffee, a walk, or something else?")
        }

        // Length gate applies ONLY to plain ASCII short asks. CJK falls
        // through so short-but-loaded phrases like "串起来" reach the compound
        // branch.
        let containsCJK = raw.unicodeScalars.contains { Self.isCJK($0) }
        if !containsCJK, raw.count < 12 {
            return .single
        }

        // Compound decision — err toward single unless we see strong signal:
        //   join cue alone ("plan a walk"/"串起来") is decisive.
        //   OR (2+ verbs AND (time-span OR 2+ categories))
        //   OR (sequencing cue AND 2+ verbs) — one sequencing token alone is
        //     too noisy ("second" often means "the second item", not "step 2").
        //   OR (2+ categories AND time-span) — even without a strong verb,
        //     "coffee and lunch for tomorrow morning" is unambiguously plural.
        let compound =
            joinCue ||
            (verbCount >= 2 && (timeSpan || categoryHits.count >= 2)) ||
            (sequencing && verbCount >= 2) ||
            (categoryHits.count >= 2 && timeSpan)

        if compound {
            return .suspectCompound(signals: HeuristicSignals(
                verbCount: verbCount,
                categoryHits: categoryHits,
                hasSequencingCue: sequencing,
                hasTimeSpan: timeSpan,
                hasJoinCue: joinCue
            ))
        }
        return .single
    }

    /// Rough CJK detection — covers Han, Hangul, and Hiragana/Katakana. Used
    /// only to skip the ASCII length gate; not exhaustive.
    nonisolated private static func isCJK(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (0x4E00...0x9FFF).contains(v)  // CJK Unified Ideographs
            || (0x3400...0x4DBF).contains(v)  // CJK Extension A
            || (0x3040...0x309F).contains(v)  // Hiragana
            || (0x30A0...0x30FF).contains(v)  // Katakana
            || (0xAC00...0xD7AF).contains(v)  // Hangul Syllables
    }

    // MARK: - LLM plan request

    struct RawPlanJSON: Decodable {
        struct Step: Decodable {
            let goal: String
            let expected_tool: String?
            let reflect_after: Bool?
        }
        let intent: String              // "compound" | "single" | "clarify"
        let steps: [Step]?
        let clarify_question: String?
        let rationale: String?
    }

    private func requestCompoundPlan(
        transcript: String, signals: HeuristicSignals, locale: Locale
    ) async throws -> TurnPlan {
        let toolNames = VoiceAgentToolRouter.allTools.map(\.name).joined(separator: ", ")
        let lang = locale.identifier.hasPrefix("zh") ? "Chinese" : "the user's language"
        let system = """
        You are the planner sub-agent of Solo Compass. Given the user's next
        turn transcript, decide whether it is one small ask (`single`), a
        clearly multi-step ask (`compound`), or so ambiguous it needs one
        clarifying question (`clarify`).

        RESPOND ONLY WITH JSON in this exact shape, no prose:
        {
          "intent": "single" | "compound" | "clarify",
          "steps": [
            {"goal": "<short imperative in \(lang)>", "expected_tool": "<one of: \(toolNames)>", "reflect_after": <bool>}
          ],
          "clarify_question": "<one question, in \(lang), or null>",
          "rationale": "<one short sentence in English, for telemetry>"
        }
        RULES:
        - `steps` is REQUIRED for `intent="compound"`, must contain 2 to 5 steps ordered by execution.
        - Every step's `expected_tool` MUST be one of the tools listed above, exactly.
        - `reflect_after: true` on any step whose result could invalidate later steps.
        - `clarify_question` is REQUIRED for `intent="clarify"`, else null.
        - `rationale` MUST be one short English sentence.
        - Never include prose outside the JSON object. Never wrap in ```json fences.
        """

        let heuristicHint = "heuristic_signals: verbs=\(signals.verbCount) categories=\(signals.categoryHits) sequencing=\(signals.hasSequencingCue) time_span=\(signals.hasTimeSpan) join=\(signals.hasJoinCue)"

        let messages: [VoiceAgentSession.Message] = [
            .init(role: .system, content: system),
            .init(role: .user, content: "\(heuristicHint)\n\ntranscript: \(transcript)"),
        ]

        // No tools — planner turn must not itself make tool calls. Keeps
        // budget separate from the main turn.
        let response = try await aiService.sendAgentMessage(messages: messages, tools: [])

        guard let raw = response.content, !raw.isEmpty else {
            throw PlannerError.emptyResponse
        }
        // Strip a stray ```json fence if the model ignored instructions.
        let stripped = Self.stripCodeFences(raw)
        guard let data = stripped.data(using: .utf8) else {
            throw PlannerError.notUTF8
        }
        let parsed = try JSONDecoder().decode(RawPlanJSON.self, from: data)

        return try Self.materialize(parsed)
    }

    nonisolated static func materialize(_ raw: RawPlanJSON) throws -> TurnPlan {
        switch raw.intent {
        case "single":
            return .single(rationale: raw.rationale ?? "llm:single")
        case "clarify":
            guard let q = raw.clarify_question, !q.isEmpty else {
                throw PlannerError.missingClarifyQuestion
            }
            return .clarify(question: q, rationale: raw.rationale ?? "llm:clarify")
        case "compound":
            let steps = (raw.steps ?? []).map {
                PlannedStep(
                    goal: $0.goal,
                    expectedTool: $0.expected_tool,
                    reflectAfter: $0.reflect_after ?? false
                )
            }
            guard steps.count >= 2 else {
                throw PlannerError.compoundNeedsAtLeastTwoSteps
            }
            return .compound(steps: steps, rationale: raw.rationale ?? "llm:compound")
        default:
            throw PlannerError.unknownIntent(raw.intent)
        }
    }

    nonisolated static func stripCodeFences(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix("```") {
            // Drop first fence line
            if let range = out.range(of: "\n") {
                out = String(out[range.upperBound...])
            }
        }
        if out.hasSuffix("```") {
            out = String(out.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out
    }

    enum PlannerError: Error, LocalizedError {
        case emptyResponse
        case notUTF8
        case missingClarifyQuestion
        case compoundNeedsAtLeastTwoSteps
        case unknownIntent(String)

        var errorDescription: String? {
            switch self {
            case .emptyResponse: return "Planner returned empty content"
            case .notUTF8: return "Planner response not UTF-8"
            case .missingClarifyQuestion: return "Planner said clarify but produced no question"
            case .compoundNeedsAtLeastTwoSteps: return "Compound plan needs at least 2 steps"
            case .unknownIntent(let s): return "Unknown intent: \(s)"
            }
        }
    }

    // MARK: - Heuristic dictionaries

    /// English + pinyin. Keep short — extensive vocab lives on the LLM side.
    static let actionVerbs: [String] = [
        "find", "get", "show", "grab", "walk", "eat", "have", "check",
        "plan", "recommend", "search", "explore", "add", "save", "look",
    ]
    static let actionVerbsCJK: [String] = [
        "找", "吃", "喝", "看", "去", "推荐", "规划", "加", "收藏", "串",
    ]

    static let categoryTokens: [String] = [
        "coffee", "cafe", "café", "food", "eat", "dinner", "lunch", "breakfast",
        "brunch", "bar", "cocktail", "wine", "museum", "gallery", "park",
        "walk", "hike", "shop", "shopping", "market", "spa", "gym",
    ]
    static let categoryTokensCJK: [String] = [
        "咖啡", "早餐", "早饭", "午餐", "午饭", "晚餐", "晚饭", "夜宵",
        "酒吧", "小酒", "博物馆", "美术馆", "画廊", "公园", "散步", "逛街",
        "商场", "菜市场", "市场",
    ]

    static let sequencingCues: [String] = [
        "then", "after that", "after", "before", "first", "second", "next",
        "and then", "later",
    ]
    static let sequencingCuesCJK: [String] = [
        "先", "再", "然后", "之后", "接着", "最后",
    ]

    static let timeSpanCues: [String] = [
        "morning", "afternoon", "evening", "night", "tomorrow", "today",
        "weekend", "half day", "full day", "a day",
    ]
    static let timeSpanCuesCJK: [String] = [
        "早上", "上午", "中午", "下午", "傍晚", "晚上", "一天", "半天", "周末",
    ]

    static let joinCues: [String] = [
        "plan a walk", "string these together", "string together",
        "route", "itinerary", "one walk", "walking tour",
    ]
    static let joinCuesCJK: [String] = [
        "串起来", "串一起", "规划一下", "一条路线", "一天玩", "一日游", "路线",
    ]
}

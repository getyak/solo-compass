import Foundation

/// ④ Self-eval Rubric — deterministic heuristic scorer.
///
/// Design principles:
/// - **No model round-trip.** Every finished turn scores itself
///   synchronously so we can run this on-device without racing the next
///   user input. The AI-critic upgrade is a separate slice (⑧); this
///   file must run in <1ms for the largest realistic transcript.
/// - **Pure function.** `score(...)` takes what it needs, returns a
///   `RubricReport` — no touching disk, network, or globals.
/// - **Heuristics tuned for the observed failure modes.** Skeletons =
///   generic filler, model-hallucinated tool intent = "let me check…"
///   text without a tool call, cards-in-lieu-of-text = long inline
///   experience card + short text (that's the *good* shape, not bad).
@MainActor
public struct RubricScorer {

    public struct TurnInput {
        public let turnIndex: Int
        public let userText: String
        public let assistantText: String
        public let toolCallsInvoked: [String]  // names, in order
        public let cardsAppended: Int
        public let synthesisQuality: AIService.AISynthesisQuality
        public let hasScopedExperience: Bool

        public init(
            turnIndex: Int,
            userText: String,
            assistantText: String,
            toolCallsInvoked: [String],
            cardsAppended: Int,
            synthesisQuality: AIService.AISynthesisQuality,
            hasScopedExperience: Bool
        ) {
            self.turnIndex = turnIndex
            self.userText = userText
            self.assistantText = assistantText
            self.toolCallsInvoked = toolCallsInvoked
            self.cardsAppended = cardsAppended
            self.synthesisQuality = synthesisQuality
            self.hasScopedExperience = hasScopedExperience
        }
    }

    public init() {}

    public func score(_ input: TurnInput) -> RubricReport {
        let assistant = input.assistantText
        let assistantLower = assistant.lowercased()
        let user = input.userText
        let userLower = user.lowercased()

        // ── relevance ────────────────────────────────────────────────
        // Cheap-but-useful signal: does the assistant echo any content
        // token from the user? An answer that shares zero content words
        // with the question is almost always off-topic.
        let userTokens = Self.contentTokens(userLower)
        let assistantTokens = Self.contentTokens(assistantLower)
        let overlap = userTokens.intersection(assistantTokens).count
        var relevance: Int
        if assistant.isEmpty {
            relevance = 0
        } else if userTokens.isEmpty {
            // Very short user turn ("好的", "嗯") — accept anything non-empty
            relevance = 8
        } else if overlap == 0 && input.cardsAppended == 0 {
            relevance = 3
        } else {
            // 8 baseline, +1 per shared content token, cap at 10
            relevance = min(10, 8 + overlap)
        }

        // ── factuality ───────────────────────────────────────────────
        // Skeleton fallbacks and hallucinated tool intent are the two
        // observed hard failure modes. Cards or an actually-invoked
        // tool anchor claims to a real source.
        var factuality: Int
        switch input.synthesisQuality {
        case .real:      factuality = 10
        case .cached:    factuality = 9
        case .skeleton:  factuality = 5   // filler content, mark down
        }
        if input.cardsAppended > 0 {
            factuality = min(10, factuality + 1)
        }
        // "let me check…" text without a tool call = pretend action.
        if Self.pretendsToInvokeTool(assistantLower) && input.toolCallsInvoked.isEmpty {
            factuality = max(0, factuality - 4)
        }

        // ── conciseness ──────────────────────────────────────────────
        // Sub-goal: keep text short when a card is doing the heavy
        // lifting; still allow long-form when the user asked "why"/"how".
        let charCount = assistant.count
        let userAsksForDepth = userLower.contains("为什么") || userLower.contains("怎么") ||
                               userLower.contains("why") || userLower.contains("how")
        let target = userAsksForDepth ? 500 : (input.cardsAppended > 0 ? 200 : 350)
        let conciseness: Int
        if charCount == 0 {
            conciseness = 0
        } else if charCount <= target {
            conciseness = 10
        } else {
            let over = charCount - target
            conciseness = max(3, 10 - (over / max(target, 1) * 4))
        }

        // ── contextUsage ─────────────────────────────────────────────
        // If a scoped experience is bound, the assistant should refer
        // to *some* real anchor (a place name substring, "here", "这里",
        // "this place") — otherwise it's ignoring the context handoff.
        var contextUsage: Int
        if !input.hasScopedExperience {
            contextUsage = 10   // no context to use, no way to fail
        } else if assistant.isEmpty {
            contextUsage = 0
        } else {
            let contextMarkers = ["这里", "这家", "这个", "here", "this place", "this spot", "there"]
            let refersToContext = contextMarkers.contains { assistantLower.contains($0) }
                                  || input.cardsAppended > 0
            contextUsage = refersToContext ? 10 : 4
        }

        // ── toolHonesty ──────────────────────────────────────────────
        // Same pattern the factuality penalty uses, but this axis is
        // graded independently so ⑧ sc-loop can see the specific issue.
        let toolHonesty: Int
        if Self.pretendsToInvokeTool(assistantLower) && input.toolCallsInvoked.isEmpty {
            toolHonesty = 2
        } else {
            toolHonesty = 10
        }

        // ── cardCoverage ─────────────────────────────────────────────
        // Bonus dimension: encourage inline cards where the user asked
        // for recommendations. If the user asked for places and the
        // assistant produced neither cards nor named places, that's a
        // dead-end answer.
        let asksForPlaces = userLower.contains("推荐") || userLower.contains("附近") ||
                            userLower.contains("哪") || userLower.contains("recommend") ||
                            userLower.contains("nearby") || userLower.contains("where")
        let cardCoverage: Int
        if asksForPlaces {
            cardCoverage = input.cardsAppended > 0 ? 10 : 4
        } else {
            // Cards are still nice-to-have but not required
            cardCoverage = 8
        }

        // Build the pre-notes report so we can compute weakestDimension
        // once, then rebuild with the diagnostic string attached.
        let pre = RubricReport(
            turnIndex: input.turnIndex,
            relevance: relevance,
            factuality: factuality,
            conciseness: conciseness,
            contextUsage: contextUsage,
            toolHonesty: toolHonesty,
            cardCoverage: cardCoverage
        )
        // Notes stay empty when nothing is actually pulling the score
        // down — a 100/100 turn with a diagnostic string attached would
        // be a scoring bug of its own.
        let weakestScore = min(relevance, factuality, conciseness,
                               contextUsage, toolHonesty, cardCoverage)
        let diagnostic = weakestScore < 10
            ? Self.notes(for: pre.weakestDimension, input: input)
            : ""
        return RubricReport(
            id: pre.id,
            turnIndex: input.turnIndex,
            createdAt: pre.createdAt,
            relevance: relevance,
            factuality: factuality,
            conciseness: conciseness,
            contextUsage: contextUsage,
            toolHonesty: toolHonesty,
            cardCoverage: cardCoverage,
            notes: diagnostic
        )
    }

    // MARK: - Helpers

    /// Drop stopwords, punctuation, whitespace; return the remaining
    /// lowercased tokens as a set for overlap counting.
    ///
    /// CJK doesn't put spaces between words, so a naïve letter/digit
    /// split treats each contiguous run of Han characters as ONE token
    /// ("附近安静咖啡馆"). Overlap between question and answer then
    /// collapses to zero even when they share every noun. We split CJK
    /// into 2-char bigrams (the smallest span that carries meaning)
    /// while keeping ASCII on word boundaries as before.
    private static func contentTokens(_ text: String) -> Set<String> {
        let stopwords: Set<String> = [
            "的", "是", "在", "有", "了", "吗", "呢", "啊", "我", "你", "他", "她",
            "the", "a", "an", "is", "are", "was", "were", "to", "of", "in", "on",
            "at", "and", "or", "but", "for", "with", "i", "you", "he", "she", "it",
            "me", "we", "they", "this", "that", "these", "those", "please"
        ]
        var out = Set<String>()
        let raw = text.unicodeScalars.split(whereSeparator: {
            !CharacterSet.letters.contains($0) && !CharacterSet.decimalDigits.contains($0)
        })
        for chunk in raw {
            let s = String(String.UnicodeScalarView(chunk))
            if isCJKRun(s) {
                // 2-char sliding-window bigrams for CJK. Single-char
                // tokens are too noisy (particles etc.), bigrams give
                // us roughly word-level granularity.
                let chars = Array(s)
                if chars.count >= 2 {
                    for i in 0...(chars.count - 2) {
                        let bigram = String(chars[i...(i + 1)])
                        if !stopwords.contains(bigram) {
                            out.insert(bigram)
                        }
                    }
                }
            } else if s.count >= 2 && !stopwords.contains(s) {
                out.insert(s)
            }
        }
        return out
    }

    /// True iff every character in the string is in the CJK Unified
    /// Ideographs block. Punctuation has already been stripped by the
    /// splitter, so this just gates the bigram path.
    private static func isCJKRun(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        for scalar in s.unicodeScalars {
            let v = scalar.value
            // CJK Unified Ideographs (main block) + extension A. Enough
            // for zh-Hans / zh-Hant / kanji-in-Japanese and skips
            // Hiragana/Katakana/Hangul — those already split on spaces.
            let inMain = (0x4E00 ... 0x9FFF).contains(v)
            let inExtA = (0x3400 ... 0x4DBF).contains(v)
            if !(inMain || inExtA) { return false }
        }
        return true
    }

    /// The "pretend to invoke a tool" pattern: assistant text implies
    /// action ("let me check", "I'll look up") without an actual tool
    /// call landing in `toolCallsInvoked`.
    private static func pretendsToInvokeTool(_ text: String) -> Bool {
        let markers = [
            "let me check", "let me look", "i'll look up", "i'll check",
            "checking now", "one moment", "让我查", "让我看看", "我来找",
            "我帮你搜索", "稍等我"
        ]
        return markers.contains { text.contains($0) }
    }

    private static func notes(for dimension: String, input: TurnInput) -> String {
        switch dimension {
        case "relevance":
            return "assistant text shares no content tokens with the user prompt"
        case "factuality":
            return input.synthesisQuality == .skeleton
                ? "synthesis fell back to skeleton — retry with a real model call"
                : "hard claims lack a tool-result anchor"
        case "conciseness":
            return "reply overshoots the target length for this turn shape"
        case "contextUsage":
            return "scoped experience is bound but assistant text ignores it"
        case "toolHonesty":
            return "assistant text implies a tool call that never landed"
        case "cardCoverage":
            return "user asked for places but no inline card was produced"
        default:
            return ""
        }
    }
}

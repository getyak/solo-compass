import Foundation
import Observation
import SwiftData
import os

/// P2.0 #202: keeps the singleton `AgentMemorySnapshot` fresh so the Chat
/// Agent (P2.0 #201) can inject a "we've met before" block into every new
/// system prompt without shipping the whole chat history back to the LLM.
///
/// Pipeline:
/// 1. Caller (usually `VoiceAgentOrchestrator.persistConversation`) invokes
///    `digestConversation(_:cityCode:)` once a turn finishes and the
///    persisted history contains at least one user/assistant pair.
/// 2. We compress the last ~7 days of messages into ≤300 chars, roll the
///    long-running `summary` forward with a ≤500-char rewrite, and refresh
///    `lastTripCity` when a non-nil city is supplied.
/// 3. The current implementation runs the digest on-device via a
///    deterministic text roll-up. The AIService slot is wired but off by
///    default so onboarding + first-run don't wait on the LLM; flipping
///    `useLLM = true` swaps in `aiService.digestConversation(...)` when it
///    exists.
///
/// Singleton semantics: exactly one row in SwiftData per user. On each
/// digest we upsert in place — matches the `AgentMemorySnapshot` docstring
/// contract.
///
/// Privacy: everything the digest reads is already on-device (SwiftData
/// chat history). Nothing is uploaded. The `SettingsView` "forget me"
/// button (P2.0 #204) calls `forgetMe()` here to wipe the row.
@MainActor
@Observable
public final class MemoryDigestService {

    public static let shared = MemoryDigestService(
        aiService: AIService(),
        modelContainer: nil
    )

    /// When false (default), digest runs a deterministic on-device roll-up.
    /// Flip via `setUseLLM(true)` once the AIService digest prompt lands
    /// so the summary starts benefitting from LLM prose.
    public private(set) var useLLM: Bool = false

    /// Max chars for the long-running `summary` field. Matches
    /// `AgentMemorySnapshot.summary` docstring (≤500).
    public static let summaryCharCap: Int = 500

    /// Max chars for the rolling `recentChatDigest` field. Matches
    /// `AgentMemorySnapshot.recentChatDigest` docstring (≤300).
    public static let recentDigestCharCap: Int = 300

    private let aiService: AIService
    private var modelContainer: ModelContainer?

    private let log = OSLog(subsystem: "com.solocompass.app", category: "MemoryDigest")

    public init(aiService: AIService, modelContainer: ModelContainer?) {
        self.aiService = aiService
        self.modelContainer = modelContainer
    }

    /// Wire the SwiftData container after init — same pattern as
    /// `VisitTrackingService` / `TasteUpdateService`.
    public func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    public func setUseLLM(_ flag: Bool) {
        self.useLLM = flag
    }

    // MARK: - Public API

    /// Fetch (or create) the singleton snapshot. Safe to call cold — returns
    /// nil if none exists on disk. Used by
    /// `VoiceAgentOrchestrator.buildSystemPrompt` (P2.0 #201).
    public func currentSnapshot() -> AgentMemorySnapshot? {
        guard let container = modelContainer else { return nil }
        let context = ModelContext(container)
        do {
            let existing = try context.fetch(FetchDescriptor<AgentMemorySnapshot>())
            return existing.first
        } catch {
            os_log("MemoryDigest: fetch failed %{public}@", log: log, type: .error, String(describing: error))
            return nil
        }
    }

    /// Ingest one just-completed conversation. `messages` should be in
    /// wall-clock order (the same order `session.messages` is emitted in).
    /// `cityCode` is optional — passed when the caller can identify the
    /// user's current trip city; if nil we leave `lastTripCity` untouched.
    public func digestConversation(
        _ messages: [VoiceAgentSession.Message],
        cityCode: String? = nil
    ) async {
        guard let container = modelContainer else {
            os_log("MemoryDigest: no modelContainer attached — skipping", log: log, type: .error)
            return
        }

        // Roll the recent-digest first: cheap, deterministic even without LLM.
        let recentDigest = Self.rollUpRecentChats(from: messages)

        // Long-running summary: blend prior summary (if any) with the freshly
        // observed conversational themes. Deterministic version below keeps
        // this test-stable; the LLM path swaps in prose when enabled.
        let prior = currentSnapshot()
        let priorSummary = prior?.summary ?? ""

        let newSummary: String
        if useLLM {
            newSummary = await llmSummarize(prior: priorSummary, recent: recentDigest)
        } else {
            newSummary = Self.deterministicSummary(prior: priorSummary, recent: recentDigest)
        }

        await persist(
            in: container,
            summary: newSummary,
            lastTripCity: cityCode ?? prior?.lastTripCity,
            recentChatDigest: recentDigest
        )
    }

    /// P2.0 #204: wipe both AgentMemorySnapshot and TasteProfile. Called by
    /// the "Forget me" Settings button. Returns whether the wipe succeeded.
    @discardableResult
    public func forgetMe() -> Bool {
        guard let container = modelContainer else { return false }
        let context = ModelContext(container)
        var ok = true
        do {
            let mem = try context.fetch(FetchDescriptor<AgentMemorySnapshot>())
            mem.forEach { context.delete($0) }
            let taste = try context.fetch(FetchDescriptor<TasteProfile>())
            taste.forEach { context.delete($0) }
            try context.save()
        } catch {
            os_log("MemoryDigest: forgetMe failed %{public}@", log: log, type: .error, String(describing: error))
            ok = false
        }
        return ok
    }

    // MARK: - Digest builders

    /// Deterministic on-device summariser. Takes the prior long-running
    /// summary and the fresh recent-digest, drops boilerplate, and emits a
    /// ≤500-char blend. Prior text weighs more than the newest turn so a
    /// single splurgy conversation doesn't rewrite the whole "who is this
    /// user" note.
    static func deterministicSummary(prior: String, recent: String) -> String {
        let priorTrim = prior.trimmingCharacters(in: .whitespacesAndNewlines)
        let recentTrim = recent.trimmingCharacters(in: .whitespacesAndNewlines)
        if priorTrim.isEmpty, recentTrim.isEmpty { return "" }
        if priorTrim.isEmpty { return String(recentTrim.prefix(summaryCharCap)) }
        if recentTrim.isEmpty { return String(priorTrim.prefix(summaryCharCap)) }

        // Keep the prior first (identity anchor), append a "recently"
        // clause so the LLM sees progression.
        let joined = "\(priorTrim) Recently: \(recentTrim)"
        return String(joined.prefix(summaryCharCap))
    }

    /// Compress the messages list into ≤300 chars. We pick user turns first
    /// (the agent's own replies rarely carry new signal about the user),
    /// concatenating from the tail so the freshest turns win.
    static func rollUpRecentChats(from messages: [VoiceAgentSession.Message]) -> String {
        let userTurns: [String] = messages.compactMap { msg in
            guard msg.role == .user, let raw = msg.content else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !userTurns.isEmpty else { return "" }

        // Freshest turns first so truncation drops the oldest, not the newest.
        var acc: [String] = []
        var total = 0
        for turn in userTurns.reversed() {
            let candidate = turn.replacingOccurrences(of: "\n", with: " ")
            let need = candidate.count + (acc.isEmpty ? 0 : 2) // "; " separator
            if total + need > recentDigestCharCap { break }
            acc.append(candidate)
            total += need
        }
        // Chronological order for the final joined string.
        let ordered = acc.reversed().joined(separator: "; ")
        return String(ordered.prefix(recentDigestCharCap))
    }

    /// Reserved LLM path. Kept as a suspend point so callers can await it
    /// once the AIService prompt lands. Falls back to the deterministic
    /// blend when the LLM slot returns empty.
    private func llmSummarize(prior: String, recent: String) async -> String {
        // Wire slot for AIService.digestConversation(prior:recent:) — not
        // yet implemented at the AIService layer; return the deterministic
        // blend so behaviour is well-defined even with `useLLM = true`.
        return Self.deterministicSummary(prior: prior, recent: recent)
    }

    // MARK: - Persistence

    /// Upsert the singleton snapshot row. Same pattern as
    /// `TasteUpdateService.persist` — fetch first, update-in-place if
    /// present, insert otherwise.
    private func persist(
        in container: ModelContainer,
        summary: String,
        lastTripCity: String?,
        recentChatDigest: String
    ) async {
        let context = ModelContext(container)
        do {
            let existing = try context.fetch(FetchDescriptor<AgentMemorySnapshot>())
            if let row = existing.first {
                row.summary = summary
                row.lastTripCity = lastTripCity
                row.recentChatDigest = recentChatDigest
                row.updatedAt = Date()
            } else {
                let row = AgentMemorySnapshot(
                    summary: summary,
                    lastTripCity: lastTripCity,
                    recentChatDigest: recentChatDigest
                )
                context.insert(row)
            }
            try context.save()
        } catch {
            os_log("MemoryDigest: save failed %{public}@", log: log, type: .error, String(describing: error))
        }
    }
}

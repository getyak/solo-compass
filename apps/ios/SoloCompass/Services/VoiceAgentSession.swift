import Foundation
import Observation

/// State + message history for one multi-turn voice agent conversation.
///
/// US-VA-01: pure model layer. No UI, no network, no SwiftData. Sequence:
///   1. `appendUser(_:)` after speech-to-text resolves a phrase.
///   2. Transition to `.thinking` while DeepSeek runs (US-VA-02 will own
///      the actual HTTP call).
///   3. If the model returns `tool_calls`, switch to `.toolExecuting`,
///      run them locally, then `appendToolResult(...)` for each and loop.
///   4. When the model returns plain `content`, `appendAssistant(...)`
///      and transition to `.speaking`, then back to `.idle` (or
///      `.listening` for the next turn).
///
/// All transitions and message bookkeeping happen on the main actor so
/// the @Observable bindings the UI consumes never cross actor boundaries.
@MainActor
@Observable
public final class VoiceAgentSession {

    // MARK: - Hard limits (PRD §5.1)
    //
    // Pinned as `static let` so US-VA-06 (loop orchestration) and tests
    // can reference the same numbers without reaching into the PRD.

    /// Maximum messages kept in `messages` before `compactIfNeeded()`
    /// summarises the oldest pairs into a single system note. Includes
    /// the initial system prompt; PRD §5.1 spec is 10 + system, here
    /// we count system in the limit for simplicity (so 11 effective).
    public static let messagesMaxCount = 11

    /// Maximum `tool_calls` we will execute from a single assistant
    /// turn. DeepSeek can return more; we reject the surplus to keep
    /// runtime bounded.
    public static let toolCallsMaxPerTurn = 5

    /// Maximum `thinking ↔ toolExecuting` recursion within one user
    /// turn. After this many loops the agent must produce plain
    /// content or the turn aborts.
    public static let recursionDepthMax = 3

    /// Wall-clock ceiling per user turn (transcribe + thinks + tools).
    public static let turnTimeoutSeconds: TimeInterval = 30

    /// How many `visibleExperiences` summaries to inject in the
    /// per-turn system continuation (PRD §6.2).
    public static let visibleExperiencesInjected = 5

    // MARK: - Types

    /// OpenAI-compatible role. We model `.tool` separately from
    /// `.assistant` because DeepSeek requires the `tool_call_id` field
    /// only on `tool` rows.
    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    /// A pending tool call returned by the model. Arguments stay as
    /// raw JSON text because the router (US-VA-03) decodes them per
    /// tool — every tool has its own argument schema.
    public struct ToolCall: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let argumentsJSON: String

        public init(id: String, name: String, argumentsJSON: String) {
            self.id = id
            self.name = name
            self.argumentsJSON = argumentsJSON
        }
    }

    /// Single entry in the conversation. Only one of `content` /
    /// `toolCalls` is set for an assistant row; tool rows always have
    /// `content` (the JSON result) + `toolCallId`.
    public struct Message: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let role: Role
        public let content: String?
        public let toolCalls: [ToolCall]
        public let toolCallId: String?
        /// For tool rows: name of the tool that produced this result.
        /// Optional because OpenAI's tool message spec accepts it but
        /// doesn't require it.
        public let name: String?

        public init(
            id: UUID = UUID(),
            role: Role,
            content: String? = nil,
            toolCalls: [ToolCall] = [],
            toolCallId: String? = nil,
            name: String? = nil
        ) {
            self.id = id
            self.role = role
            self.content = content
            self.toolCalls = toolCalls
            self.toolCallId = toolCallId
            self.name = name
        }
    }

    /// Agent loop states (PRD §5.1 diagram).
    public enum State: Equatable, Sendable {
        case idle
        case listening
        case transcribing
        case thinking
        case toolExecuting(toolCount: Int)
        case speaking
    }

    /// Why a session ended. The view binds to this to decide what to
    /// show after the sheet closes.
    public enum EndReason: String, Sendable {
        case userClose
        case timeout
        case error
        case quotaExceeded
    }

    // MARK: - Observable state

    public private(set) var state: State = .idle
    public private(set) var messages: [Message] = []
    public private(set) var turnCount: Int = 0
    /// Recursion depth within the current user turn (thinking →
    /// toolExecuting → thinking …). Reset by `beginUserTurn()`.
    public private(set) var recursionDepth: Int = 0
    /// Set after `end(reason:)`. Sticky — the session is done.
    public private(set) var endReason: EndReason?

    // MARK: - Init

    public init() {}

    // MARK: - Public transitions
    //
    // All transitions are deliberately gated through these methods so a
    // future test can verify "you cannot go from .idle directly to
    // .toolExecuting", etc.

    /// Seed the conversation with a system prompt. Call once at the
    /// start of a session, before any `beginUserTurn()`.
    public func seedSystem(_ prompt: String) {
        precondition(messages.isEmpty, "system prompt must be first")
        messages.append(Message(role: .system, content: prompt))
    }

    /// Clear the conversation and re-seed with a fresh system prompt.
    ///
    /// US-002: used by `VoiceAgentOrchestrator.rebindContext(_:)` to swap
    /// experience scope on a live session without reallocating the
    /// orchestrator or its AI/Voice service dependencies. Resets
    /// `turnCount`, `recursionDepth`, and `state` so the next turn starts
    /// from a clean slate. If the session was already ended, this
    /// reactivates it for reuse.
    public func reseedSystem(_ prompt: String) {
        messages.removeAll()
        turnCount = 0
        recursionDepth = 0
        state = .idle
        endReason = nil
        messages.append(Message(role: .system, content: prompt))
    }

    /// Seed a restored conversation's history after the system prompt has been
    /// seeded. Appends the stored (non-system) messages in order so the chat
    /// reopens exactly where it left off. `turnCount` is bumped to the number of
    /// restored user turns so compaction/limits behave sensibly going forward.
    public func restoreHistory(_ restored: [Message]) {
        let nonSystem = restored.filter { $0.role != .system }
        guard !nonSystem.isEmpty else { return }
        messages.append(contentsOf: nonSystem)
        turnCount = nonSystem.filter { $0.role == .user }.count
        recursionDepth = 0
        state = .idle
        compactIfNeeded()
    }

    /// Transition .idle → .listening. Caller is the long-press gesture.
    public func beginListening() {
        guard endReason == nil else { return }
        state = .listening
    }

    /// Transition .listening → .transcribing once the mic is released
    /// and speech-to-text starts producing a final transcript.
    public func beginTranscribing() {
        guard state == .listening else { return }
        state = .transcribing
    }

    /// Start a new user turn. Appends the user transcript, resets
    /// recursion depth, increments `turnCount`, transitions to
    /// `.thinking`. Compacts history if it would overflow.
    public func beginUserTurn(transcript: String) {
        guard endReason == nil else { return }
        guard !transcript.isEmpty else { return }
        messages.append(Message(role: .user, content: transcript))
        turnCount += 1
        recursionDepth = 0
        state = .thinking
        compactIfNeeded()
    }

    /// Append an assistant turn. If `toolCalls` is non-empty the agent
    /// must transition to `.toolExecuting`; otherwise to `.speaking`.
    /// Returns the resulting state so the caller can chain on it.
    @discardableResult
    public func appendAssistantTurn(
        content: String?,
        toolCalls: [ToolCall]
    ) -> State {
        let capped = Array(toolCalls.prefix(Self.toolCallsMaxPerTurn))
        messages.append(Message(role: .assistant, content: content, toolCalls: capped))
        if capped.isEmpty {
            state = .speaking
        } else {
            recursionDepth += 1
            state = .toolExecuting(toolCount: capped.count)
        }
        return state
    }

    /// Append one tool result. The view-model fans these in once for
    /// every entry in the prior assistant turn's `toolCalls`.
    public func appendToolResult(
        toolCallId: String,
        name: String,
        resultJSON: String
    ) {
        messages.append(Message(
            role: .tool, content: resultJSON,
            toolCallId: toolCallId, name: name
        ))
    }

    /// All tool results for this round are in — go back to `.thinking`
    /// so the next DeepSeek call can react to them.
    public func resumeThinkingAfterTools() {
        guard case .toolExecuting = state else { return }
        state = .thinking
    }

    /// Final assistant text shown; transition to .speaking → .idle so
    /// the UI can render the reply and wait for the next turn.
    public func finishSpeakingTurn() {
        guard state == .speaking else { return }
        state = .idle
    }

    /// Inject a system-role message mid-conversation (e.g. budget overflow
    /// notice). Called by the orchestrator to steer the model without
    /// adding a user turn that increments `turnCount`.
    public func appendSystemContinuation(_ text: String) {
        messages.append(Message(role: .system, content: text))
    }

    /// Terminate the session. Idempotent — only the first call wins.
    public func end(reason: EndReason) {
        guard endReason == nil else { return }
        endReason = reason
        state = .idle
    }

    // MARK: - Predicates

    /// True when we've spent the recursion budget for the current
    /// user turn; the next assistant response MUST be plain content
    /// (no tool_calls) or the orchestrator aborts.
    public var hasExceededRecursionBudget: Bool {
        recursionDepth >= Self.recursionDepthMax
    }

    /// True when the session has ended for any reason.
    public var isEnded: Bool { endReason != nil }

    /// Text of the most recently committed assistant message, if any. The
    /// orchestrator reads this for the final spoken/displayed reply instead of
    /// relying on the live `streamingContent` buffer (which is cleared as soon
    /// as the text lands here, to avoid a duplicate bubble).
    public var lastAssistantText: String? {
        for msg in messages.reversed() where msg.role == .assistant {
            if let content = msg.content, !content.isEmpty { return content }
        }
        return nil
    }

    // MARK: - History compaction (PRD §5.2)

    /// If `messages.count` exceeds `messagesMaxCount`, replace the
    /// middle slice with a synthesised system summary, keeping:
    /// - the original system prompt (index 0, if present)
    /// - the two most recent user/assistant pairs
    /// This is a lossy compression for cost; the orchestrator should
    /// avoid relying on long-distance pronoun resolution.
    func compactIfNeeded() {
        guard messages.count > Self.messagesMaxCount else { return }

        // Pull the leading system prompt aside if there is one.
        var head: [Message] = []
        var rest = messages
        if let first = rest.first, first.role == .system {
            head.append(first)
            rest.removeFirst()
        }

        // Keep the most recent 4 messages (~2 user/assistant pairs).
        let tailKeep = 4
        guard rest.count > tailKeep else { return }
        let dropping = rest.dropLast(tailKeep)
        let tail = Array(rest.suffix(tailKeep))

        // Build a coarse summary. We pull at most 3 user turns for
        // the summary; verbosity here costs tokens forever.
        let userSnippets = dropping
            .filter { $0.role == .user }
            .compactMap { $0.content }
            .suffix(3)
        let summary: String
        if userSnippets.isEmpty {
            summary = "Earlier turns omitted to stay within the model context budget."
        } else {
            summary = "Earlier user turns (summarised): "
                + userSnippets.joined(separator: " | ")
        }

        let summaryMsg = Message(role: .system, content: summary)
        messages = head + [summaryMsg] + tail
    }
}

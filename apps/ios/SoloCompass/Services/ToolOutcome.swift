import Foundation

/// Structured outcome of a tool call, richer than the legacy `{"ok":bool}` shape.
///
/// Wire format handed back to the model as JSON, e.g.:
/// ```json
/// {"ok": true,  "outcome": "ok",                "payload": {...}}
/// {"ok": false, "outcome": "retryable",         "reason": "empty_result",
///  "hint": "Try widening radius_meters to 5000 or dropping the category filter.",
///  "retryable_with": {"radius_meters": 5000}}
/// {"ok": false, "outcome": "fatal",             "reason": "map_unavailable",
///  "hint": "The map session isn't active; ask the user to reopen the map."}
/// {"ok": false, "outcome": "needs_confirmation","reason": "paywall_required",
///  "hint": "Ask the user whether to open the paywall for open_blindbox."}
/// ```
///
/// `ok` is kept as a mirror of `outcome == .ok` so pre-existing chat
/// transcripts that reference the legacy shape still parse — the new
/// `outcome`/`reason`/`hint` fields are additive.
///
/// The router uses `ToolOutcome` internally with a strongly-typed payload;
/// `encodeForModel()` produces the wire dictionary.
enum ToolOutcome<Payload: Encodable> {
    case ok(payload: Payload, hint: String? = nil)
    /// Same tool may succeed if the model adjusts args per `hint` /
    /// `retryableWith`. Router raises `same (tool,reason)` count each time
    /// and forces `.fatal` after `ToolRetryLedger.retryCap` to break death spirals.
    case retryable(reason: RetryReason, hint: String, retryableWith: [String: EncodableValue]? = nil, partial: Payload? = nil)
    case fatal(reason: FatalReason, hint: String)
    case needsConfirmation(reason: ConfirmationReason, question: String, payload: Payload? = nil)

    /// Machine-readable failure taxonomy for retryable outcomes. The `rawValue`
    /// is what appears as `"reason"` in the wire envelope; it is also the key
    /// the router uses for its `(tool, reason)` retry counter.
    enum RetryReason: String, Encodable {
        case emptyResult = "empty_result"
        case invalidArgs = "invalid_args"
        case notFound = "not_found"
        case notEnoughContext = "not_enough_context"
        case transientUpstream = "transient_upstream"
    }

    /// Fatal reasons — hard stop for THIS tool this turn. The router will not
    /// re-dispatch the same (tool, reason) even if the model re-emits it.
    enum FatalReason: String, Encodable {
        case unknownTool = "unknown_tool"
        case mapUnavailable = "map_unavailable"
        case dependencyUnavailable = "dependency_unavailable"
        case unrecoverableUpstream = "unrecoverable_upstream"
        case retryBudgetExhausted = "retry_budget_exhausted"
        case malformedResponse = "malformed_response"
    }

    /// Requires an out-of-band user answer before the tool can succeed.
    enum ConfirmationReason: String, Encodable {
        case paywallRequired = "paywall_required"
        case destructiveActionPending = "destructive_action_pending"
        case ambiguousReferent = "ambiguous_referent"
    }
}

// MARK: - Side effect classification

/// Static per-tool classification. Downstream ⑤ speculative execution only
/// runs `.none` and `.visual` tools ahead of the model's full arg emission.
enum ToolSideEffect: String {
    case none          // pure read (recall_pattern, sos_plan stub)
    case visual        // map/UI mutation only (explore_nearby, filter_visible)
    case mutating      // SwiftData / UserDefaults write (save_to_favorites, bury_capsule)
    case external      // opens external app / crosses trust boundary (navigate_to)
}

// MARK: - Encoding helpers

/// Type-erasing wrapper for the tiny slice of JSON values that
/// `retryable_with` needs (numbers, strings, bools). Keeps the envelope
/// JSON-clean without pulling in AnyCodable.
enum EncodableValue: Encodable {
    case int(Int)
    case double(Double)
    case string(String)
    case bool(Bool)

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let v):    try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .bool(let v):   try c.encode(v)
        }
    }
}

/// Minimal JSON tree used by the envelope so it can pass through a strict
/// `Encodable` without leaking `Any`.
indirect enum JSONValue: Encodable {
    case string(String)
    case double(Double)
    case int(Int)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    static func from(_ any: Any) -> JSONValue {
        switch any {
        case let v as String:  return .string(v)
        case let v as Bool:    return .bool(v)
        case let v as Int:     return .int(v)
        case let v as Double:  return .double(v)
        case is NSNull:        return .null
        case let arr as [Any]: return .array(arr.map { JSONValue.from($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { JSONValue.from($0) })
        default: return .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .bool(let v):   try c.encode(v)
        case .null:          try c.encodeNil()
        case .array(let a):  try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

/// Wire envelope handed to the model. File-scope (not nested in the generic
/// `encodeForModel()`) because Swift forbids nested types inside generic
/// functions — the memberwise init disappears otherwise. Every `ToolOutcome`
/// case flattens into this shape.
struct ToolOutcomeEnvelope: Encodable {
    let ok: Bool
    let outcome: String
    let reason: String?
    let hint: String?
    let payload: JSONValue?
    let retryable_with: [String: EncodableValue]?
    let question: String?
}

extension ToolOutcome {
    /// JSON string that the router hands back as the `tool` role message body.
    /// The one place all four cases meet the wire.
    func encodeForModel() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let envelope: ToolOutcomeEnvelope
        switch self {
        case let .ok(payload, hint):
            envelope = ToolOutcomeEnvelope(
                ok: true, outcome: "ok",
                reason: nil, hint: hint,
                payload: Self.jsonValue(from: payload),
                retryable_with: nil, question: nil
            )
        case let .retryable(reason, hint, retryableWith, partial):
            envelope = ToolOutcomeEnvelope(
                ok: false, outcome: "retryable",
                reason: reason.rawValue, hint: hint,
                payload: partial.flatMap(Self.jsonValue(from:)),
                retryable_with: retryableWith, question: nil
            )
        case let .fatal(reason, hint):
            envelope = ToolOutcomeEnvelope(
                ok: false, outcome: "fatal",
                reason: reason.rawValue, hint: hint,
                payload: nil, retryable_with: nil, question: nil
            )
        case let .needsConfirmation(reason, question, payload):
            envelope = ToolOutcomeEnvelope(
                ok: false, outcome: "needs_confirmation",
                reason: reason.rawValue, hint: nil,
                payload: payload.flatMap(Self.jsonValue(from:)),
                retryable_with: nil, question: question
            )
        }

        guard let data = try? encoder.encode(envelope),
              let s = String(data: data, encoding: .utf8) else {
            // Never lose the outcome discriminant even if payload serialisation blew up.
            return #"{"ok":false,"outcome":"fatal","reason":"malformed_response","hint":"Router failed to serialise the tool outcome."}"#
        }
        return s
    }

    private static func jsonValue<T: Encodable>(from value: T) -> JSONValue? {
        guard let data = try? JSONEncoder().encode(value),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return JSONValue.from(parsed)
    }
}

// MARK: - Retry counter

/// Per-turn budget of same (tool, reason) retryable outcomes before the router
/// forces a `.fatal` — breaks the classic tool-calling death spiral where the
/// model keeps re-issuing the same bad argument. Kept internal so the
/// orchestrator can `resetForNewTurn()` at each user turn boundary.
@MainActor
final class ToolRetryLedger {
    /// After this many retries of the SAME (tool, reason), the router escalates
    /// to `.fatal(reason: .retryBudgetExhausted, …)`. 2 = "try once, retry
    /// once, third occurrence is fatal" — enough for a hint to land, tight
    /// enough that a stuck model can't burn a whole turn.
    static let retryCap = 2

    private var counts: [Key: Int] = [:]

    struct Key: Hashable {
        let tool: String
        let reason: String
    }

    /// Record a retryable occurrence and report the new count.
    @discardableResult
    func record(tool: String, reason: String) -> Int {
        let k = Key(tool: tool, reason: reason)
        let next = (counts[k] ?? 0) + 1
        counts[k] = next
        return next
    }

    /// True when the (tool, reason) has already burned its retries — the caller
    /// must escalate to `.fatal(reason: .retryBudgetExhausted, ...)`.
    func isExhausted(tool: String, reason: String) -> Bool {
        (counts[Key(tool: tool, reason: reason)] ?? 0) > Self.retryCap
    }

    /// Called by the orchestrator at each new user turn so retries reset per
    /// turn (not per session — a fresh turn = fresh chance).
    func resetForNewTurn() { counts.removeAll(keepingCapacity: true) }

    /// Test helper.
    func snapshot() -> [String: Int] {
        Dictionary(uniqueKeysWithValues: counts.map { ("\($0.key.tool):\($0.key.reason)", $0.value) })
    }
}

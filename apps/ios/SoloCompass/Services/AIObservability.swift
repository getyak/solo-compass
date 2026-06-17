import Foundation
import os
import Sentry

/// Token usage and AI pipeline observability.
/// Collects per-call metrics (token counts, latency, model kind) and
/// emits them as Sentry breadcrumbs + os.Logger entries so we can
/// measure synthesis quality, cost, and tool-call distribution.
@MainActor
public final class AIObservability {

    public static let shared = AIObservability()

    private static let logger = Logger(subsystem: "com.solocompass", category: "AIObservability")

    // MARK: - Token usage tracking

    public struct TokenUsage: Sendable {
        public let promptTokens: Int
        public let completionTokens: Int
        public let totalTokens: Int
        public let model: String
        public let kind: String
        public let latencyMs: Int
        public let cached: Bool

        public init(
            promptTokens: Int,
            completionTokens: Int,
            totalTokens: Int,
            model: String,
            kind: String,
            latencyMs: Int,
            cached: Bool = false
        ) {
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.totalTokens = totalTokens
            self.model = model
            self.kind = kind
            self.latencyMs = latencyMs
            self.cached = cached
        }
    }

    /// Running session totals.
    public private(set) var sessionPromptTokens: Int = 0
    public private(set) var sessionCompletionTokens: Int = 0
    public private(set) var sessionCalls: Int = 0
    public private(set) var sessionCacheHits: Int = 0

    private init() {}

    /// Record token usage from a completed API response.
    /// Call this after parsing the OpenAI-compatible response's `usage` block.
    public func record(_ usage: TokenUsage) {
        sessionPromptTokens += usage.promptTokens
        sessionCompletionTokens += usage.completionTokens
        sessionCalls += 1
        if usage.cached { sessionCacheHits += 1 }

        Self.logger.info("ai_call: \(usage.kind, privacy: .public) model=\(usage.model, privacy: .public) prompt=\(usage.promptTokens) completion=\(usage.completionTokens) latency=\(usage.latencyMs)ms cached=\(usage.cached)")

        SentrySDK.addBreadcrumb(Self.makeBreadcrumb(usage))
    }

    // MARK: - Event tracking

    public enum AIEvent: String {
        case synthesisSuccess = "ai.synthesis.success"
        case synthesisSkeletonFallback = "ai.synthesis.skeleton"
        case synthesisCacheHit = "ai.synthesis.cache_hit"
        case chatTurnCompleted = "ai.chat.turn"
        case toolCallExecuted = "ai.tool.executed"
        case routeGenerated = "ai.route.generated"
        case routeAdopted = "ai.route.adopted"
        case quotaExceeded = "ai.quota.exceeded"
        case exploreCompleted = "ai.explore.completed"
    }

    /// Track a discrete AI pipeline event with optional metadata.
    public func trackEvent(
        _ event: AIEvent,
        metadata: [String: String] = [:]
    ) {
        Self.logger.info("ai_event: \(event.rawValue, privacy: .public) \(metadata.description, privacy: .public)")

        let crumb = Breadcrumb(level: .info, category: "ai.pipeline")
        crumb.message = event.rawValue
        crumb.data = metadata.isEmpty ? nil : metadata
        SentrySDK.addBreadcrumb(crumb)
    }

    // MARK: - Tool call distribution

    public private(set) var toolCallCounts: [String: Int] = [:]

    public func recordToolCall(name: String) {
        toolCallCounts[name, default: 0] += 1
        trackEvent(.toolCallExecuted, metadata: ["tool": name])
    }

    // MARK: - Session summary

    public var sessionSummary: [String: Any] {
        [
            "total_calls": sessionCalls,
            "prompt_tokens": sessionPromptTokens,
            "completion_tokens": sessionCompletionTokens,
            "cache_hits": sessionCacheHits,
            "tool_calls": toolCallCounts,
        ]
    }

    // MARK: - Private

    nonisolated private static func makeBreadcrumb(_ usage: TokenUsage) -> Breadcrumb {
        let crumb = Breadcrumb(level: .info, category: "ai.token_usage")
        crumb.message = "\(usage.kind): \(usage.totalTokens) tokens (\(usage.latencyMs)ms)"
        crumb.data = [
            "model": usage.model,
            "kind": usage.kind,
            "prompt_tokens": usage.promptTokens,
            "completion_tokens": usage.completionTokens,
            "latency_ms": usage.latencyMs,
            "cached": usage.cached,
        ]
        return crumb
    }

    /// Extract token usage from an OpenAI-compatible JSON response.
    /// Returns nil if the `usage` block is missing (streaming responses).
    nonisolated public static func extractUsage(
        from json: [String: Any],
        model: String,
        kind: String,
        latencyMs: Int
    ) -> TokenUsage? {
        guard let usage = json["usage"] as? [String: Any] else { return nil }
        let prompt = usage["prompt_tokens"] as? Int ?? 0
        let completion = usage["completion_tokens"] as? Int ?? 0
        let total = usage["total_tokens"] as? Int ?? (prompt + completion)
        let cached = (usage["prompt_cache_hit_tokens"] as? Int ?? 0) > 0
        return TokenUsage(
            promptTokens: prompt,
            completionTokens: completion,
            totalTokens: total,
            model: model,
            kind: kind,
            latencyMs: latencyMs,
            cached: cached
        )
    }
}

import Foundation

/// High-level AI task classification for model routing decisions.
/// Maps task intent to the optimal model/provider combination.
///
/// This is a planning layer ABOVE `AIService.ModelKind`. ModelKind
/// controls which env-var override and quota bucket to use; AITaskType
/// controls which model *family* is best for the task. Today they
/// collapse to the same DeepSeek endpoint (`deepseek-flash`), but the
/// routing matrix is ready for a future multi-model split.
///
/// Research basis: arxiv.org/abs/2509.13487 found DeepSeek-AI leads at
/// 93.3% for structured tasks vs Claude 3.5 Sonnet at 80.0%.
/// See docs/architecture/SYSTEM_IMPROVEMENT_PLAN.md §2.3.
public enum AITaskType: String, CaseIterable, Sendable {
    /// Intent detection, category mapping — fast, cheap, high structured accuracy.
    case classification
    /// POI field extraction from raw text into typed JSON.
    case structuredExtract
    /// Experience description generation — narrative quality matters.
    case narrativeSynth
    /// Chat agent dialogue — tool-use, multi-turn context.
    case conversational
    /// Solo score computation — currently rule-based, future ML.
    case ranking
}

/// Routes AI tasks to the optimal model configuration.
/// Encapsulates the routing matrix so callers declare *what* they need,
/// not *which model* to use.
public enum AIModelRouter {

    /// Per-task model routing knobs (kind, temperature, token cap, optional override).
    public struct ModelConfig: Sendable {
        public let modelKind: AIService.ModelKind
        public let temperature: Double
        public let maxTokens: Int
        /// When multi-model routing is enabled, this overrides the model name.
        /// nil = use the default for modelKind (from Secrets/env).
        public let modelOverride: String?

        public init(
            modelKind: AIService.ModelKind,
            temperature: Double,
            maxTokens: Int,
            modelOverride: String? = nil
        ) {
            self.modelKind = modelKind
            self.temperature = temperature
            self.maxTokens = maxTokens
            self.modelOverride = modelOverride
        }
    }

    /// Map a task type to model configuration. Today all tasks route to
    /// DeepSeek (`deepseek-flash`) via the existing ModelKind path. The
    /// per-task env overrides all read DeepSeek model vars so a stale
    /// Anthropic model setting can never pin a built-in route.
    public static func config(for taskType: AITaskType) -> ModelConfig {
        switch taskType {
        case .classification:
            return ModelConfig(
                modelKind: .synthesis,
                temperature: 0.1,
                maxTokens: 256,
                modelOverride: envOverride("DEEPSEEK_MODEL_CLASSIFICATION")
            )
        case .structuredExtract:
            return ModelConfig(
                modelKind: .synthesis,
                temperature: 0.2,
                maxTokens: 2048,
                modelOverride: envOverride("DEEPSEEK_MODEL_EXTRACT")
            )
        case .narrativeSynth:
            return ModelConfig(
                modelKind: .synthesis,
                temperature: 0.7,
                maxTokens: 2048,
                modelOverride: envOverride("DEEPSEEK_MODEL_SYNTHESIS")
            )
        case .conversational:
            return ModelConfig(
                modelKind: .voice,
                temperature: 0.3,
                maxTokens: 512,
                modelOverride: envOverride("DEEPSEEK_MODEL_VOICE")
            )
        case .ranking:
            return ModelConfig(
                modelKind: .synthesis,
                temperature: 0.0,
                maxTokens: 512,
                modelOverride: nil
            )
        }
    }

    /// Resolve a per-task model override from the environment. Legacy
    /// DeepSeek ids (`deepseek-chat`, `deepseek-reasoner`, `deepseek-v4-pro`,
    /// `deepseek-v4-flash`) normalize forward to `deepseek-flash` so a stale
    /// env pin cannot keep a built-in route on an old model; explicit
    /// non-DeepSeek model ids pass through untouched.
    private static func envOverride(_ key: String) -> String? {
        let value = ProcessInfo.processInfo.environment[key] ?? ""
        guard !value.isEmpty else { return nil }
        return Secrets.normalizeDeepSeekModel(value)
    }
}

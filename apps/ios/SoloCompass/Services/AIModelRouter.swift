import Foundation

/// High-level AI task classification for model routing decisions.
/// Maps task intent to the optimal model/provider combination.
///
/// This is a planning layer ABOVE `AIService.ModelKind`. ModelKind
/// controls which env-var override and quota bucket to use; AITaskType
/// controls which model *family* is best for the task. Today they
/// collapse to the same DeepSeek endpoint, but the routing matrix is
/// ready for multi-model splits (DeepSeek for structured extraction,
/// Claude for narrative synthesis).
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
    /// DeepSeek via the existing ModelKind path. When multi-model routing
    /// ships, classification/structuredExtract stay on DeepSeek while
    /// narrativeSynth/conversational move to Claude.
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
                modelOverride: envOverride("ANTHROPIC_MODEL_SYNTHESIS")
            )
        case .conversational:
            return ModelConfig(
                modelKind: .voice,
                temperature: 0.3,
                maxTokens: 512,
                modelOverride: envOverride("ANTHROPIC_MODEL_CHAT")
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

    private static func envOverride(_ key: String) -> String? {
        let value = ProcessInfo.processInfo.environment[key] ?? ""
        return value.isEmpty ? nil : value
    }
}

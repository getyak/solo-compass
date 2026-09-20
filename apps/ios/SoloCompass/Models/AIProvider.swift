import Foundation

/// The backend service used for AI-powered recommendations and extraction.
public enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case deepseek
    case openai
    case custom

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .openai: return "OpenAI"
        case .custom: return NSLocalizedString("ai.provider.custom", comment: "Custom AI provider")
        }
    }

    var icon: String {
        switch self {
        case .deepseek: return "brain"
        case .openai: return "sparkle"
        case .custom: return "gearshape"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com/v1"
        case .openai: return "https://api.openai.com/v1"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek: return "deepseek-flash"
        case .openai: return "gpt-4o-mini"
        case .custom: return ""
        }
    }

    /// Recognize persisted defaults from older releases when switching providers.
    static let legacyDeepSeekModels: Set<String> = [
        "deepseek-chat", "deepseek-reasoner", "deepseek-v4-pro", "deepseek-v4-flash",
    ]

    func modelAfterSwitching(from currentModel: String) -> String {
        let knownDefaults = Self.allCases.map(\.defaultModel)
        if knownDefaults.contains(currentModel) || Self.legacyDeepSeekModels.contains(currentModel) {
            return defaultModel
        }
        return currentModel
    }

    var accentColor: String {
        switch self {
        case .deepseek: return "blue"
        case .openai: return "green"
        case .custom: return "purple"
        }
    }
}

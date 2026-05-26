import Foundation

public enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case deepseek
    case openai
    case custom

    var id: String { rawValue }

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
        case .deepseek: return "deepseek-chat"
        case .openai: return "gpt-4o-mini"
        case .custom: return ""
        }
    }

    var accentColor: String {
        switch self {
        case .deepseek: return "blue"
        case .openai: return "green"
        case .custom: return "purple"
        }
    }
}

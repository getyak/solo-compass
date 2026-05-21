import SwiftUI
import Observation

/// Persists and vends the active app theme.
@Observable
@MainActor
public final class ThemeService {
    public static let shared = ThemeService()

    public enum ThemeOption: String, CaseIterable, Identifiable {
        case system = "System"
        case obsidian = "Obsidian"
        public var id: String { rawValue }
        public var localizedName: String { rawValue }
    }

    public var currentTheme: any Theme { Self.theme(for: selectedOption) }

    public var selectedOption: ThemeOption {
        didSet {
            UserDefaults.standard.set(selectedOption.rawValue, forKey: "selectedTheme")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "selectedTheme")
            .flatMap(ThemeOption.init(rawValue:)) ?? .system
        selectedOption = saved
    }

    private static func theme(for option: ThemeOption) -> any Theme {
        switch option {
        case .system: return SystemTheme()
        case .obsidian: return ObsidianTheme()
        }
    }
}

// MARK: - Environment

private struct ThemeServiceKey: EnvironmentKey {
    static let defaultValue: ThemeService = ThemeService.shared
}

extension EnvironmentValues {
    public var themeService: ThemeService {
        get { self[ThemeServiceKey.self] }
        set { self[ThemeServiceKey.self] = newValue }
    }
}

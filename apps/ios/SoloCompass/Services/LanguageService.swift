import Foundation
import Observation

/// In-app language switcher.
///
/// iOS apps normally inherit the system language. We override that by writing
/// to the `AppleLanguages` UserDefaults key — the value is read by `Bundle`
/// on next launch to pick the matching `.lproj`. A relaunch is required for
/// the change to take effect (a hard iOS constraint without bundle swizzling).
@MainActor
@Observable
public final class LanguageService {
    /// The languages a traveler can pick from in settings, plus the option to follow the device.
    public enum Option: String, CaseIterable, Identifiable, Sendable {
        case system
        case english = "en"
        case simplifiedChinese = "zh-Hans"

        public var id: String { rawValue }

        /// `nil` for `.system` — fall back to `Locale.current`.
        public var locale: Locale? {
            switch self {
            case .system:            return nil
            case .english:           return Locale(identifier: "en")
            case .simplifiedChinese: return Locale(identifier: "zh-Hans")
            }
        }
    }

    public static let shared = LanguageService()

    /// UserDefaults key honoured by `Bundle` to pick the active `.lproj`.
    static let appleLanguagesKey = "AppleLanguages"
    /// Our own override marker so we can distinguish "user picked system"
    /// from "AppleLanguages happens to match the system language".
    static let overrideKey = "SoloCompass.LanguageOverride"

    public private(set) var current: Option

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.overrideKey),
           let option = Option(rawValue: raw) {
            self.current = option
        } else {
            self.current = .system
        }
    }

    /// Effective locale to pass to AI / formatters. Falls back to system
    /// when the user picked `.system`.
    public var effectiveLocale: Locale {
        current.locale ?? .current
    }

    /// Persist the user's choice. Returns `true` when a relaunch is needed
    /// for UI strings to actually swap (always true except for no-op writes).
    @discardableResult
    public func setLanguage(_ option: Option) -> Bool {
        guard option != current else { return false }
        current = option

        switch option {
        case .system:
            defaults.removeObject(forKey: Self.overrideKey)
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        case .english, .simplifiedChinese:
            defaults.set(option.rawValue, forKey: Self.overrideKey)
            defaults.set([option.rawValue], forKey: Self.appleLanguagesKey)
        }
        return true
    }
}

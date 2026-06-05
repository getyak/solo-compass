import Foundation

// MARK: - Runtime Key Resolution
//
// `GeneratedSecrets.swift` is gitignored and re-emitted on every build by
// `scripts/generate_secrets.sh` from the repo-root `.env`.
//
// `SecretsRuntime.swift` is committed and provides computed properties that
// prefer a UserDefaults-stored key (entered by the user in Settings) over the
// build-time baked-in value. This lets open-source / TestFlight users supply
// their own DeepSeek key without re-building.
//
// US-001: Resolution goes through an `APIKeyResolver` seam so unit tests can
// inject an empty-key resolver and exercise the unconfigured-state branch
// even on dev machines whose `.env` bakes in a real DeepSeek key.

/// Resolves the effective DeepSeek API key for the current process.
/// Production uses `DefaultAPIKeyResolver`; tests can swap in
/// `EmptyAPIKeyResolver` (or a custom one) via `Secrets.apiKeyResolver`.
protocol APIKeyResolver {
    func resolveDeepSeekAPIKey() -> String
}

/// Production resolver: UserDefaults override → build-time baked key.
struct DefaultAPIKeyResolver: APIKeyResolver {
    func resolveDeepSeekAPIKey() -> String {
        if let override = UserDefaults.standard.string(forKey: Secrets.RuntimeKeys.deepSeekApiKey),
           !override.isEmpty {
            return override
        }
        return Secrets.deepSeekApiKey
    }
}

/// Test resolver: always returns an empty key so the unconfigured branch fires.
struct EmptyAPIKeyResolver: APIKeyResolver {
    func resolveDeepSeekAPIKey() -> String { "" }
}

extension Secrets {
    enum RuntimeKeys {
        static let deepSeekApiKey = "runtimeDeepSeekKey"
        /// US-013: per-process UserDefaults override for the Foursquare key.
        /// Lets devs / TestFlight users plug in a key without re-building.
        static let foursquareApiKey = "runtimeFoursquareKey"
        /// US-003: per-process UserDefaults override for the OpenWeather key.
        /// Lets devs / TestFlight users plug in a key without re-building.
        static let openWeatherApiKey = "runtimeOpenWeatherKey"
        // In-app AI provider settings (written by AIProviderSettingsView via UserPreferences).
        // These shadow the build-time GeneratedSecrets values when non-empty.
        static let aiApiKey = "runtimeAIApiKey"
        static let aiBaseURL = "runtimeAIBaseURL"
        static let aiModelName = "runtimeAIModelName"
        static let aiProvider = "runtimeAIProvider"
    }

    /// Active resolver — swap in tests via `Secrets.apiKeyResolver = EmptyAPIKeyResolver()`
    /// and restore to `DefaultAPIKeyResolver()` afterwards.
    nonisolated(unsafe) static var apiKeyResolver: APIKeyResolver = DefaultAPIKeyResolver()

    /// Effective AI API key. Resolution chain:
    /// 1. In-app UserPreferences (set via AIProviderSettingsView)
    /// 2. UserDefaults runtime override (dev/test injection)
    /// 3. Build-time GeneratedSecrets (`.env` baked key)
    static var resolvedDeepSeekApiKey: String {
        let prefs = UserPreferences()
        if !prefs.aiApiKey.isEmpty {
            return prefs.aiApiKey
        }
        return apiKeyResolver.resolveDeepSeekAPIKey()
    }

    /// Effective base URL. Prefers in-app setting, falls back to
    /// build-time `deepSeekBaseURL`, then the DeepSeek default.
    static var resolvedDeepSeekBaseURL: String {
        let prefs = UserPreferences()
        if !prefs.aiBaseURL.isEmpty {
            return prefs.aiBaseURL
        }
        return deepSeekBaseURL.isEmpty ? AIProvider.deepseek.defaultBaseURL : deepSeekBaseURL
    }

    /// Effective model name. Prefers in-app setting, falls back to
    /// build-time `deepSeekModel`, then the DeepSeek default.
    static var resolvedDeepSeekModel: String {
        let prefs = UserPreferences()
        if !prefs.aiModelName.isEmpty {
            return prefs.aiModelName
        }
        return deepSeekModel.isEmpty ? AIProvider.deepseek.defaultModel : deepSeekModel
    }

    /// Effective Foursquare API key: UserDefaults override → build-time baked.
    /// Returns "" when neither is set; callers must gate on empty so they
    /// never make a request with an absent key (US-013).
    static var resolvedFoursquareKey: String {
        if let override = UserDefaults.standard.string(forKey: RuntimeKeys.foursquareApiKey),
           !override.isEmpty {
            return override
        }
        return foursquareApiKey
    }

    /// Effective OpenWeather API key (US-003). Resolution chain:
    /// 1. UserDefaults runtime override (dev/test injection)
    /// 2. Build-time baked key (`GeneratedSecrets.openWeatherApiKey`)
    ///
    /// Returns `nil` when no key is configured so `WeatherService` can throw
    /// `WeatherError.noAPIKey` and degrade gracefully (NowScore falls back to
    /// non-weather signals when weather is unavailable).
    static var openWeatherAPIKey: String? {
        if let override = UserDefaults.standard.string(forKey: RuntimeKeys.openWeatherApiKey),
           !override.isEmpty {
            return override
        }
        return openWeatherApiKey.isEmpty ? nil : openWeatherApiKey
    }
}

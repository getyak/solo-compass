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
    }

    /// Active resolver — swap in tests via `Secrets.apiKeyResolver = EmptyAPIKeyResolver()`
    /// and restore to `DefaultAPIKeyResolver()` afterwards.
    nonisolated(unsafe) static var apiKeyResolver: APIKeyResolver = DefaultAPIKeyResolver()

    /// Effective DeepSeek API key. Reads through `apiKeyResolver`.
    /// Returns "" when neither override nor baked key is set; callers map
    /// empty → `AIError.missingAPIKey` / `.unconfigured`.
    static var resolvedDeepSeekApiKey: String {
        apiKeyResolver.resolveDeepSeekAPIKey()
    }

    static var resolvedDeepSeekBaseURL: String {
        deepSeekBaseURL.isEmpty ? "https://api.deepseek.com/v1" : deepSeekBaseURL
    }

    static var resolvedDeepSeekModel: String {
        deepSeekModel.isEmpty ? "deepseek-chat" : deepSeekModel
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
}

import Foundation

/// Build-time feature flags for staging Epic E rollout.
///
/// Flags are read from `Resources/FeatureFlags.plist`; missing keys
/// fall back to the defaults defined here. Override per-build by
/// editing the plist or setting the matching env var prefixed `FF_`.
public enum FeatureFlags {
    /// Master switch for all Supabase-backed code paths (auth, sync,
    /// Edge Functions). When false, every backend call is a no-op
    /// returning empty / .success — the app must remain fully usable
    /// (PRD G7 local-first invariant).
    ///
    /// Default: false in beta.1, will flip to true in beta.3.
    public static var backendSync: Bool {
        readBool("FF_BACKEND_SYNC", default: false)
    }

    /// When true, AIService.synthesizeExperiences calls the Supabase
    /// Edge Function instead of Anthropic directly. Requires
    /// backendSync to also be true. Off in beta.1 so QA can still
    /// hit Anthropic via the local key for prompt-tuning.
    public static var routeAIThroughEdge: Bool {
        readBool("FF_ROUTE_AI_THROUGH_EDGE", default: false)
    }

    /// When true, explanation and voice intents still call Anthropic
    /// directly from the device (using the env-var key). Used as a
    /// staged rollout gate: synthesis moves to the Edge Function first
    /// (US-034) while explanation/voice migrate later. Off by default.
    public static var localAIFallback: Bool {
        readBool("FF_LOCAL_AI_FALLBACK", default: false)
    }

    // MARK: - Internals

    static func readBool(_ key: String, default fallback: Bool) -> Bool {
        if let env = ProcessInfo.processInfo.environment[key] {
            return env == "1" || env.lowercased() == "true"
        }
        guard let url = Bundle.main.url(forResource: "FeatureFlags", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return fallback }
        return (plist[key] as? Bool) ?? fallback
    }
}

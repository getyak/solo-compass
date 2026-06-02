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
    /// Edge Function instead of DeepSeek directly. Requires backendSync
    /// to also be true. Off in beta.1 so QA can still hit DeepSeek via
    /// the local key for prompt-tuning.
    public static var routeAIThroughEdge: Bool {
        readBool("FF_ROUTE_AI_THROUGH_EDGE", default: false)
    }

    /// When true, explanation and voice intents still call DeepSeek
    /// directly from the device (using the local key). Used as a staged
    /// rollout gate: synthesis moves to the Edge Function first
    /// (US-034) while explanation/voice migrate later. Off by default.
    public static var localAIFallback: Bool {
        readBool("FF_LOCAL_AI_FALLBACK", default: false)
    }

    /// When true, AgentRouter (Intent→Query→Guide pipeline) is used in place of
    /// the legacy VoiceAgentOrchestrator. Default on; set FF_AGENT_ROUTER_ENABLED=0
    /// to fall back to the old path while the flag is still in place.
    public static var agentRouterEnabled: Bool {
        readBool("FF_AGENT_ROUTER_ENABLED", default: true)
    }

    /// DEBUG-only. When true, SKStoreReviewController.requestReview() fires
    /// immediately on any markCompleted() call, bypassing the 3-completion
    /// threshold and the reviewPromptShown guard. Use this to verify the
    /// prompt appears in Simulator without completing 3 real experiences.
    /// Always false in Release builds — the #if DEBUG guard in
    /// UserPreferences.requestReviewIfEligible() strips it at compile time.
    public static var forceReviewPrompt: Bool {
        readBool("FF_FORCE_REVIEW_PROMPT", default: false)
    }

    /// When true and the user is Pro, `MapViewModel.exploreNearby` runs the
    /// 4-ring radial schedule (1.5 / 3 / 6 / 12 km) instead of the single
    /// 3 km query, then merges results through `OverpassService.dedupe` and
    /// feeds them to a single AI synthesis call. Pro users without the flag
    /// still get the original 1-ring behaviour. Free users are unaffected
    /// regardless. See docs/PRD/pro-radial-explore.md (US-MR-01).
    ///
    /// Default off in beta — flip to true after staged 10% rollout review.
    public static var proMultiRingExplore: Bool {
        readBool("FF_PRO_MULTI_RING_EXPLORE", default: false)
    }

    /// When true, `MapViewModel.exploreNearby` routes through `EnrichmentAgent`:
    /// a small-radius, deep-dive pass that cross-references each place across
    /// Overpass + Apple MapKit + Foursquare (real rating/hours/price) and
    /// reverse-geocoded addresses before AI synthesis. Fewer, richer entries
    /// instead of a wide ring of skeletons. When false, the legacy wide-ring
    /// pipeline runs unchanged so we can fall back instantly.
    ///
    /// Default on — the deep-dive output is strictly richer; the flag exists
    /// purely as a kill switch.
    public static var deepDiveEnrichment: Bool {
        readBool("FF_DEEP_DIVE_ENRICHMENT", default: true)
    }

    /// When true, `WebSearchEnrichmentSource` makes an additional AI call for
    /// the top-N (default 5) ranked experiences after synthesis, asking for
    /// cross-verifiable objective fields (openingHours, website, phone).
    ///
    /// Default off — each enrichment call consumes daily quota. Enable only
    /// once per-experience quota accounting lands (US-016). Set
    /// FF_WEB_SEARCH_ENRICHMENT=1 in the Simulator to trial without rebuilding.
    public static var webSearchEnrichment: Bool {
        readBool("FF_WEB_SEARCH_ENRICHMENT", default: false)
    }

    /// Companion Mode Phase 1 gate (US-007). When true, `ItineraryStore`
    /// enqueues saves/updates/deletes to the `itineraries` outbox so
    /// `SyncService` can push them to Supabase and pull remote changes.
    ///
    /// When false, all itinerary mutations still persist locally (SwiftData)
    /// but the outbox rows are never created, so no network traffic is
    /// generated. Flip to true after `0003_companion.sql` is deployed.
    ///
    /// Default off in Phase 1 beta — local-first invariant (PRD G7).
    public static var companion: Bool {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "FF_COMPANION") != nil {
            return UserDefaults.standard.bool(forKey: "FF_COMPANION")
        }
        #endif
        return readBool("FF_COMPANION", default: false)
    }

    /// DEBUG-only: feed the companion discovery with local mock posts instead of
    /// hitting the (undeployed) Edge Function, so the nearby map layer renders
    /// for demos. Requires `companion` to also be on. Compiled out of Release.
    public static var companionMock: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "FF_COMPANION_MOCK")
        #else
        return false
        #endif
    }

    /// US-009: Master gate for the in-map Companion *layer* toggle (the
    /// floating control that overlays nearby blurred presence cells). The
    /// underlying discovery still returns nil today, so the toggle is a dead
    /// button — hide it by default so users don't tap a control that never
    /// does anything (decision A).
    ///
    /// Default off. In DEBUG you can flip it on without rebuilding by setting
    /// the `FF_COMPANION_LAYER_ENABLED` UserDefaults key:
    ///
    ///     defaults write <app-bundle-id> FF_COMPANION_LAYER_ENABLED -bool YES
    ///
    /// or, in a test / debug menu, `UserDefaults.standard.set(true, forKey:
    /// "FF_COMPANION_LAYER_ENABLED")`. The override is compiled out of Release
    /// builds so production always reads the plist/env value (default false).
    public static var companionLayerEnabled: Bool {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "FF_COMPANION_LAYER_ENABLED") != nil {
            return UserDefaults.standard.bool(forKey: "FF_COMPANION_LAYER_ENABLED")
        }
        #endif
        return readBool("FF_COMPANION_LAYER_ENABLED", default: false)
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

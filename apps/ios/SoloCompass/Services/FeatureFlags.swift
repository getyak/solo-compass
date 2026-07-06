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
    /// generated.
    ///
    /// This is the master gate for the whole backend social stack — friends,
    /// DMs (ChatService), companion discovery, presence, moderation reads, and
    /// itinerary sync all check it. It also requires `backendSync` to be on for
    /// any network call to actually fire.
    ///
    /// DEBUG builds default to ON so the social / friends / moderation surfaces
    /// are immediately exercisable in the Simulator. Release builds read the
    /// plist/env (`FF_COMPANION`) and default OFF, preserving the staged-rollout
    /// posture (PRD G7 local-first invariant) until the backend is ready.
    /// Override in DEBUG without rebuilding:
    ///
    ///     defaults write <app-bundle-id> FF_COMPANION -bool NO
    public static var companion: Bool {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "FF_COMPANION") != nil {
            return UserDefaults.standard.bool(forKey: "FF_COMPANION")
        }
        if let env = ProcessInfo.processInfo.environment["FF_COMPANION"] {
            return env == "1" || env.lowercased() == "true"
        }
        return true
        #else
        return readBool("FF_COMPANION", default: false)
        #endif
    }

    /// City OS v2 master gate (PRD solo-city-os-v2 §4–5): the 落地包 landing
    /// kit, 在地 local-events module, compliance banner, city modes
    /// (Live/Plan/Recall), event map markers, the two chat tools
    /// (get_city_kit / find_local_events) and the 今日城市签 daily omen feed.
    /// Content still requires `backendSync` for network refresh — with it off,
    /// the bundled Vientiane seed keeps every surface functional offline.
    ///
    /// DEBUG builds default ON so the whole Live-mode loop is exercisable in
    /// the Simulator; Release reads plist/env (`FF_CITY_OS`) and defaults OFF
    /// for a staged rollout. Override in DEBUG without rebuilding:
    ///
    ///     defaults write <app-bundle-id> FF_CITY_OS -bool NO
    public static var cityOS: Bool {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "FF_CITY_OS") != nil {
            return UserDefaults.standard.bool(forKey: "FF_CITY_OS")
        }
        if let env = ProcessInfo.processInfo.environment["FF_CITY_OS"] {
            return env == "1" || env.lowercased() == "true"
        }
        return true
        #else
        return readBool("FF_CITY_OS", default: false)
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

    // MARK: - Developer override registry
    //
    // The Developer Options panel (revealed after a tester-email unlock) lets
    // testers flip these flags at runtime without a rebuild. Overrides are
    // stored in UserDefaults under the same `FF_` key and consulted by
    // `readBool` — see the resolution order there. Kept as data so the UI can
    // render the list generically and stays in sync as flags are added.

    /// A single developer-toggleable flag, described for the Developer Options UI.
    public struct DeveloperFlag: Identifiable, Sendable {
        /// UserDefaults / env-var key (e.g. "FF_WEB_SEARCH_ENRICHMENT").
        public let key: String
        /// Localization key for the human-readable title.
        public let titleKey: String
        /// Localization key for the one-line explanation.
        public let subtitleKey: String
        /// The compiled-in default used when no override/plist value exists.
        public let defaultValue: Bool
        public var id: String { key }
    }

    /// Flags surfaced in Developer Options. Order = display order.
    public static let developerFlags: [DeveloperFlag] = [
        DeveloperFlag(key: "FF_BACKEND_SYNC", titleKey: "dev.flag.backendSync.title",
                      subtitleKey: "dev.flag.backendSync.subtitle", defaultValue: false),
        DeveloperFlag(key: "FF_ROUTE_AI_THROUGH_EDGE", titleKey: "dev.flag.routeAIThroughEdge.title",
                      subtitleKey: "dev.flag.routeAIThroughEdge.subtitle", defaultValue: false),
        DeveloperFlag(key: "FF_PRO_MULTI_RING_EXPLORE", titleKey: "dev.flag.proMultiRingExplore.title",
                      subtitleKey: "dev.flag.proMultiRingExplore.subtitle", defaultValue: false),
        DeveloperFlag(key: "FF_DEEP_DIVE_ENRICHMENT", titleKey: "dev.flag.deepDiveEnrichment.title",
                      subtitleKey: "dev.flag.deepDiveEnrichment.subtitle", defaultValue: true),
        DeveloperFlag(key: "FF_WEB_SEARCH_ENRICHMENT", titleKey: "dev.flag.webSearchEnrichment.title",
                      subtitleKey: "dev.flag.webSearchEnrichment.subtitle", defaultValue: false),
        DeveloperFlag(key: "FF_COMPANION", titleKey: "dev.flag.companion.title",
                      subtitleKey: "dev.flag.companion.subtitle", defaultValue: false),
        DeveloperFlag(key: "FF_COMPANION_LAYER_ENABLED", titleKey: "dev.flag.companionLayer.title",
                      subtitleKey: "dev.flag.companionLayer.subtitle", defaultValue: false),
        DeveloperFlag(key: "FF_CITY_OS", titleKey: "dev.flag.cityOS.title",
                      subtitleKey: "dev.flag.cityOS.subtitle", defaultValue: false),
    ]

    /// The developer override currently stored for `key`, or nil when the
    /// tester hasn't set one (so the plist/compiled default applies).
    public static func override(for key: String) -> Bool? {
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Write (or clear, when `value == nil`) a developer override for `key`.
    public static func setOverride(_ value: Bool?, for key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Remove every developer override so all flags revert to their
    /// plist/compiled defaults. Used by the "Reset overrides" action.
    public static func clearAllOverrides() {
        for flag in developerFlags {
            UserDefaults.standard.removeObject(forKey: flag.key)
        }
    }

    // MARK: - Internals

    static func readBool(_ key: String, default fallback: Bool) -> Bool {
        // 1. Environment variable — highest priority so CI / test schemes and
        //    Xcode run-args stay deterministic.
        if let env = ProcessInfo.processInfo.environment[key] {
            return env == "1" || env.lowercased() == "true"
        }
        // 2. Developer Options runtime override (UserDefaults). Only present
        //    when a tester explicitly toggled the flag in the in-app panel, so
        //    default installs are unaffected. Works in Release too, which is
        //    what TestFlight testers run.
        if let override = override(for: key) {
            return override
        }
        // 3. Bundled FeatureFlags.plist for staged build-time config.
        guard let url = Bundle.main.url(forResource: "FeatureFlags", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return fallback }
        return (plist[key] as? Bool) ?? fallback
    }
}

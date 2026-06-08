import Foundation
import Observation
import os
import StoreKit
import UIKit

/// User preferences persisted to UserDefaults.
///
/// Designed as a single Codable blob — small, atomic writes; easy to migrate.
/// We store under a single key (`UserPreferences.storageKey`) and re-encode on
/// every mutation. With <100 entries this stays well under the 4MB practical
/// limit on UserDefaults.
@Observable
public final class UserPreferences {
    private static let logger = Logger(subsystem: "com.solocompass", category: "UserPreferences")

    /// The traveler's self-described style, used to tailor experience recommendations.
    public enum SoloTravelStyle: String, Codable, CaseIterable, Identifiable {
        case explorer, worker, foodie, cultureSeeker
        public var id: String { rawValue }
    }

    /// Snapshot used for Codable persistence. Mirrors the @Observable surface.
    private struct Snapshot: Codable {
        var preferredCategories: [ExperienceCategory] = []
        var dislikedCategories: [ExperienceCategory] = []
        var soloTravelStyle: SoloTravelStyle = .explorer
        var maxDistanceKm: Double = 5.0
        var visitHistory: [String: Date] = [:]
        var completedExperiences: Set<String> = []
        var favoritedExperiences: Set<String> = []
        var favoritedAt: [String: Date] = [:]
        var pendingCheckIns: [String: Date] = [:]
        var lastSelectedCity: String?
        var hasCompletedOnboarding: Bool = false
        var notificationsEnabled: Bool = false
        var quietHoursStart: Int = 22
        var quietHoursEnd: Int = 8
        var seedImported: Bool = false
        var swiftDataMirrored: Bool = false
        var hasAcceptedExploreConsent: Bool = false
        var exploreConsentGivenAt: Date?
        var reviewPromptShown: Bool = false
        var includeMapInExport: Bool = false
        var visibleCategories: Set<ExperienceCategory> = Set(ExperienceCategory.allCases)
        var customTags: [String] = []
        // US-013: Foursquare fallback usage tracking — visibility only,
        // no enforcement in v1. `foursquareCallsTodayDate` stamps the local
        // day the counter was last reset; mismatches roll it back to zero.
        var foursquareCallsToday: Int = 0
        var foursquareCallsTodayDate: Date?

        // AI provider settings — stored here so SecretsRuntime can read them
        // without a separate UserDefaults key namespace.
        var aiProviderRaw: String = AIProvider.deepseek.rawValue
        var aiApiKey: String = ""
        var aiBaseURL: String = ""
        var aiModelName: String = ""

        // Companion profile (US-009)
        var companionAvatarEmoji: String = "🧭"
        var companionBio: String = ""
        var companionLanguages: [String] = []
        var companionVisibilityRaw: String = CompanionVisibility.off.rawValue

        // US-008: editable display handle (2–20 chars, not unique).
        var displayHandle: String = ""

        // Companion posts keyed by ItineraryId.rawValue (US-010)
        // Stored as a simple [itinId: CompanionPost] blob. A full CompanionPostStore
        // (backed by SwiftData + Supabase sync) will supersede this in a later story.
        var activeCompanionPosts: [String: CompanionPost] = [:]

        // US-020: companion safety consent
        var hasAcceptedCompanionConsent: Bool = false
        var companionConsentGivenAt: Date?

        // US-011: A+A+A companion gating master switch (default off).
        var companionEnabled: Bool = false

        // US-029: visual strength of the RecruitingModule. Hidden from Settings UI;
        // stored so an A/B test can set it without a code change.
        var companionModuleStrengthRaw: String = ModuleStrength.restrained.rawValue

        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case preferredCategories, dislikedCategories, soloTravelStyle, maxDistanceKm
            case visitHistory, completedExperiences, favoritedExperiences, favoritedAt, pendingCheckIns
            case lastSelectedCity, hasCompletedOnboarding, notificationsEnabled
            case quietHoursStart, quietHoursEnd, seedImported, swiftDataMirrored
            case hasAcceptedExploreConsent, exploreConsentGivenAt, reviewPromptShown
            case includeMapInExport, visibleCategories, customTags
            case foursquareCallsToday, foursquareCallsTodayDate
            case aiProviderRaw, aiApiKey, aiBaseURL, aiModelName
            case companionAvatarEmoji, companionBio, companionLanguages, companionVisibilityRaw
            case displayHandle
            case activeCompanionPosts
            case hasAcceptedCompanionConsent, companionConsentGivenAt
            case companionEnabled
            case companionModuleStrengthRaw
        }

        init() {}

        init(
            preferredCategories: [ExperienceCategory],
            dislikedCategories: [ExperienceCategory],
            soloTravelStyle: SoloTravelStyle,
            maxDistanceKm: Double,
            visitHistory: [String: Date],
            completedExperiences: Set<String>,
            favoritedExperiences: Set<String>,
            favoritedAt: [String: Date],
            pendingCheckIns: [String: Date],
            lastSelectedCity: String?,
            hasCompletedOnboarding: Bool,
            notificationsEnabled: Bool,
            quietHoursStart: Int,
            quietHoursEnd: Int,
            seedImported: Bool,
            swiftDataMirrored: Bool,
            hasAcceptedExploreConsent: Bool,
            exploreConsentGivenAt: Date?,
            reviewPromptShown: Bool,
            includeMapInExport: Bool,
            visibleCategories: Set<ExperienceCategory>,
            customTags: [String],
            foursquareCallsToday: Int,
            foursquareCallsTodayDate: Date?,
            aiProviderRaw: String,
            aiApiKey: String,
            aiBaseURL: String,
            aiModelName: String,
            companionAvatarEmoji: String,
            companionBio: String,
            companionLanguages: [String],
            companionVisibilityRaw: String,
            displayHandle: String = "",
            activeCompanionPosts: [String: CompanionPost],
            hasAcceptedCompanionConsent: Bool = false,
            companionConsentGivenAt: Date? = nil,
            companionEnabled: Bool = false,
            companionModuleStrengthRaw: String = ModuleStrength.restrained.rawValue
        ) {
            self.preferredCategories = preferredCategories
            self.dislikedCategories = dislikedCategories
            self.soloTravelStyle = soloTravelStyle
            self.maxDistanceKm = maxDistanceKm
            self.visitHistory = visitHistory
            self.completedExperiences = completedExperiences
            self.favoritedExperiences = favoritedExperiences
            self.favoritedAt = favoritedAt
            self.pendingCheckIns = pendingCheckIns
            self.lastSelectedCity = lastSelectedCity
            self.hasCompletedOnboarding = hasCompletedOnboarding
            self.notificationsEnabled = notificationsEnabled
            self.quietHoursStart = quietHoursStart
            self.quietHoursEnd = quietHoursEnd
            self.seedImported = seedImported
            self.swiftDataMirrored = swiftDataMirrored
            self.hasAcceptedExploreConsent = hasAcceptedExploreConsent
            self.exploreConsentGivenAt = exploreConsentGivenAt
            self.reviewPromptShown = reviewPromptShown
            self.includeMapInExport = includeMapInExport
            self.visibleCategories = visibleCategories
            self.customTags = customTags
            self.foursquareCallsToday = foursquareCallsToday
            self.foursquareCallsTodayDate = foursquareCallsTodayDate
            self.aiProviderRaw = aiProviderRaw
            self.aiApiKey = aiApiKey
            self.aiBaseURL = aiBaseURL
            self.aiModelName = aiModelName
            self.companionAvatarEmoji = companionAvatarEmoji
            self.companionBio = companionBio
            self.companionLanguages = companionLanguages
            self.companionVisibilityRaw = companionVisibilityRaw
            self.displayHandle = displayHandle
            self.activeCompanionPosts = activeCompanionPosts
            self.hasAcceptedCompanionConsent = hasAcceptedCompanionConsent
            self.companionConsentGivenAt = companionConsentGivenAt
            self.companionEnabled = companionEnabled
            self.companionModuleStrengthRaw = companionModuleStrengthRaw
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.preferredCategories = try container.decodeIfPresent([ExperienceCategory].self, forKey: .preferredCategories) ?? []
            self.dislikedCategories = try container.decodeIfPresent([ExperienceCategory].self, forKey: .dislikedCategories) ?? []
            self.soloTravelStyle = try container.decodeIfPresent(SoloTravelStyle.self, forKey: .soloTravelStyle) ?? .explorer
            self.maxDistanceKm = try container.decodeIfPresent(Double.self, forKey: .maxDistanceKm) ?? 5.0
            self.visitHistory = try container.decodeIfPresent([String: Date].self, forKey: .visitHistory) ?? [:]
            self.completedExperiences = try container.decodeIfPresent(Set<String>.self, forKey: .completedExperiences) ?? []
            self.favoritedExperiences = try container.decodeIfPresent(Set<String>.self, forKey: .favoritedExperiences) ?? []
            self.favoritedAt = try container.decodeIfPresent([String: Date].self, forKey: .favoritedAt) ?? [:]
            self.pendingCheckIns = try container.decodeIfPresent([String: Date].self, forKey: .pendingCheckIns) ?? [:]
            self.lastSelectedCity = try container.decodeIfPresent(String.self, forKey: .lastSelectedCity)
            self.hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
            self.notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
            self.quietHoursStart = try container.decodeIfPresent(Int.self, forKey: .quietHoursStart) ?? 22
            self.quietHoursEnd = try container.decodeIfPresent(Int.self, forKey: .quietHoursEnd) ?? 8
            self.seedImported = try container.decodeIfPresent(Bool.self, forKey: .seedImported) ?? false
            self.swiftDataMirrored = try container.decodeIfPresent(Bool.self, forKey: .swiftDataMirrored) ?? false
            self.hasAcceptedExploreConsent = try container.decodeIfPresent(Bool.self, forKey: .hasAcceptedExploreConsent) ?? false
            self.exploreConsentGivenAt = try container.decodeIfPresent(Date.self, forKey: .exploreConsentGivenAt)
            self.reviewPromptShown = try container.decodeIfPresent(Bool.self, forKey: .reviewPromptShown) ?? false
            self.includeMapInExport = try container.decodeIfPresent(Bool.self, forKey: .includeMapInExport) ?? false
            self.visibleCategories = try container.decodeIfPresent(Set<ExperienceCategory>.self, forKey: .visibleCategories)
                ?? Set(ExperienceCategory.allCases)
            self.customTags = try container.decodeIfPresent([String].self, forKey: .customTags) ?? []
            self.foursquareCallsToday = try container.decodeIfPresent(Int.self, forKey: .foursquareCallsToday) ?? 0
            self.foursquareCallsTodayDate = try container.decodeIfPresent(Date.self, forKey: .foursquareCallsTodayDate)
            self.aiProviderRaw = try container.decodeIfPresent(String.self, forKey: .aiProviderRaw) ?? AIProvider.deepseek.rawValue
            self.aiApiKey = try container.decodeIfPresent(String.self, forKey: .aiApiKey) ?? ""
            self.aiBaseURL = try container.decodeIfPresent(String.self, forKey: .aiBaseURL) ?? ""
            self.aiModelName = try container.decodeIfPresent(String.self, forKey: .aiModelName) ?? ""
            self.companionAvatarEmoji = try container.decodeIfPresent(String.self, forKey: .companionAvatarEmoji) ?? "🧭"
            self.companionBio = try container.decodeIfPresent(String.self, forKey: .companionBio) ?? ""
            self.companionLanguages = try container.decodeIfPresent([String].self, forKey: .companionLanguages) ?? []
            self.companionVisibilityRaw = try container.decodeIfPresent(String.self, forKey: .companionVisibilityRaw) ?? CompanionVisibility.off.rawValue
            self.displayHandle = try container.decodeIfPresent(String.self, forKey: .displayHandle) ?? ""
            self.activeCompanionPosts = try container.decodeIfPresent([String: CompanionPost].self, forKey: .activeCompanionPosts) ?? [:]
            self.hasAcceptedCompanionConsent = try container.decodeIfPresent(Bool.self, forKey: .hasAcceptedCompanionConsent) ?? false
            self.companionConsentGivenAt = try container.decodeIfPresent(Date.self, forKey: .companionConsentGivenAt)
            self.companionEnabled = try container.decodeIfPresent(Bool.self, forKey: .companionEnabled) ?? false
            self.companionModuleStrengthRaw = try container.decodeIfPresent(String.self, forKey: .companionModuleStrengthRaw) ?? ModuleStrength.restrained.rawValue
        }
    }

    public var preferredCategories: [ExperienceCategory] { didSet { persist() } }
    public var dislikedCategories: [ExperienceCategory] { didSet { persist() } }
    public var soloTravelStyle: SoloTravelStyle { didSet { persist() } }
    public var maxDistanceKm: Double { didSet { persist() } }
    public var visitHistory: [String: Date] { didSet { persist() } }
    public var completedExperiences: Set<String> { didSet { persist() } }
    public var favoritedExperiences: Set<String> { didSet { persist() } }
    public var favoritedAt: [String: Date] { didSet { persist() } }
    public var pendingCheckIns: [String: Date] { didSet { persist() } }
    public var lastSelectedCity: String? { didSet { persist() } }
    public var hasCompletedOnboarding: Bool { didSet { persist() } }
    public var notificationsEnabled: Bool { didSet { persist() } }
    public var quietHoursStart: Int { didSet { persist() } }
    public var quietHoursEnd: Int { didSet { persist() } }
    public var seedImported: Bool { didSet { persist() } }
    /// True after legacy UserDefaults arrays for completed / favorited /
    /// pending check-ins have been mirrored into SwiftData. Set once in
    /// `attachRepository(_:)` and then never re-run.
    public var swiftDataMirrored: Bool { didSet { persist() } }
    /// True once the user has dismissed the first-run Explore-Here
    /// consent sheet (US-034). Gates the Explore button + voice intent
    /// — never blocks UI for returning users.
    public var hasAcceptedExploreConsent: Bool { didSet { persist() } }
    /// Date the user first granted Explore-Here consent (US-037).
    /// Non-nil means consent has been given; nil means the sheet must
    /// be shown before the first Overpass/AI call.
    public var exploreConsentGivenAt: Date? { didSet { persist() } }
    /// True once SKStoreReviewController.requestReview() has been triggered
    /// (after the user's 3rd distinct experience completion). Prevents repeat
    /// prompts. US-041.
    public var reviewPromptShown: Bool { didSet { persist() } }
    /// When true, MarkdownExporter embeds a 300×200 map snapshot as a
    /// base64 data: URL image in exported notes. US-020.
    public var includeMapInExport: Bool { didSet { persist() } }
    /// Subset of ExperienceCategory cases the user wants to see as pills
    /// in FilterBarView. Defaults to all 8 cases. Hiding a category drops
    /// its pill from the filter bar but does NOT affect map markers or
    /// recommendation ranking. US-006.
    public var visibleCategories: Set<ExperienceCategory> { didSet { persist() } }
    /// User-defined free-form tag pills rendered in `FilterBarView` after the
    /// 8 built-in category pills. Each entry corresponds to a value found in
    /// `Experience.userTags` and lets the user filter the map by their own
    /// labels (e.g. "sunset", "rainy-ok"). Defaults to empty. US-008.
    public var customTags: [String] { didSet { persist() } }
    /// US-013: number of Foursquare fallback calls made today. Reset on
    /// local-midnight rollover. Visibility-only in v1 (no enforcement).
    public var foursquareCallsToday: Int { didSet { persist() } }
    /// US-013: local-calendar day the counter above was last reset.
    /// When `Calendar.current.startOfDay(for: now)` differs from the
    /// stored value, `incrementFoursquareCallsToday` rolls the counter
    /// back to 1 instead of incrementing.
    public var foursquareCallsTodayDate: Date? { didSet { persist() } }

    /// Raw string backing for `aiProvider`. Stored so the Codable blob
    /// survives new provider cases being added in future releases.
    public var aiProviderRaw: String { didSet { persist() } }
    /// User-supplied API key for the selected AI provider. Stored encrypted
    /// at-rest by iOS when the app uses Data Protection; transmitted only
    /// to the configured provider endpoint.
    public var aiApiKey: String { didSet { persist() } }
    /// Base URL for the OpenAI-compatible completions endpoint.
    /// Empty string means "use the provider default".
    public var aiBaseURL: String { didSet { persist() } }
    /// Model identifier (e.g. "deepseek-chat", "gpt-4o-mini").
    /// Empty string means "use the provider default".
    public var aiModelName: String { didSet { persist() } }

    // Companion profile (US-009)

    /// Emoji avatar for the companion profile. No real photo.
    public var companionAvatarEmoji: String { didSet { persist() } }
    /// Short bio shown to other users in companion discovery.
    public var companionBio: String { didSet { persist() } }
    /// ISO language codes the user speaks (e.g. ["en", "zh"]).
    public var companionLanguages: [String] { didSet { persist() } }
    /// Raw string backing for `companionVisibility`. Default: "off".
    public var companionVisibilityRaw: String { didSet { persist() } }

    /// US-008: the user's editable display handle (2–20 chars, not unique).
    /// Stored verbatim; length/trim validation happens at the edit-UI boundary
    /// (`MyProfileEditView`). Empty string means "no handle set yet".
    public var displayHandle: String { didSet { persist() } }

    /// Typed access to companion visibility. Reads/writes `companionVisibilityRaw`.
    public var companionVisibility: CompanionVisibility {
        get { CompanionVisibility(rawValue: companionVisibilityRaw) ?? .off }
        set { companionVisibilityRaw = newValue.rawValue }
    }

    /// Active CompanionPosts keyed by ItineraryId.rawValue (US-010).
    /// A full CompanionPostStore (SwiftData + Supabase sync) will supersede this in a later story.
    public var activeCompanionPosts: [String: CompanionPost] { didSet { persist() } }

    // US-020: companion safety consent

    /// True once the user has accepted the companion safety disclaimer + age confirmation.
    /// Gates changing visibility from `.off` — the sheet must be shown first.
    public var hasAcceptedCompanionConsent: Bool { didSet { persist() } }
    /// Date the user first accepted the companion safety consent (US-020).
    public var companionConsentGivenAt: Date? { didSet { persist() } }

    /// US-011: A+A+A companion feature master switch. When false, all
    /// companion UI surfaces stay hidden regardless of visibility/consent
    /// state. Default false — the feature is opt-in.
    public var companionEnabled: Bool { didSet { persist() } }

    /// US-029: Raw string backing for `companionModuleStrength`. Not exposed in
    /// Settings UI — intended for A/B experiments only. Default: "restrained".
    public var companionModuleStrengthRaw: String { didSet { persist() } }

    /// US-029: Typed access to the visual strength of the RecruitingModule.
    /// Reads/writes `companionModuleStrengthRaw`.
    public var companionModuleStrength: ModuleStrength {
        get { ModuleStrength(rawValue: companionModuleStrengthRaw) ?? .restrained }
        set { companionModuleStrengthRaw = newValue.rawValue }
    }

    /// Typed access to the selected AI provider. Reads/writes `aiProviderRaw`.
    public var aiProvider: AIProvider {
        get { AIProvider(rawValue: aiProviderRaw) ?? .deepseek }
        set { aiProviderRaw = newValue.rawValue }
    }

    /// Optional repository handle used for double-writing user-action
    /// mutations into SwiftData. `attachRepository(_:)` wires this up
    /// once at app boot; tests usually leave it nil and rely on
    /// UserDefaults only.
    @ObservationIgnored private weak var experienceRepository: ExperienceRepository?

    private static let storageKey = "com.solocompass.userPreferences.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let snapshot = Self.load(from: defaults)
        self.preferredCategories = snapshot.preferredCategories
        self.dislikedCategories = snapshot.dislikedCategories
        self.soloTravelStyle = snapshot.soloTravelStyle
        self.maxDistanceKm = snapshot.maxDistanceKm
        self.visitHistory = snapshot.visitHistory
        self.completedExperiences = snapshot.completedExperiences
        self.favoritedExperiences = snapshot.favoritedExperiences
        self.favoritedAt = snapshot.favoritedAt
        self.pendingCheckIns = snapshot.pendingCheckIns
        self.lastSelectedCity = snapshot.lastSelectedCity
        self.hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        self.notificationsEnabled = snapshot.notificationsEnabled
        self.quietHoursStart = snapshot.quietHoursStart
        self.quietHoursEnd = snapshot.quietHoursEnd
        self.seedImported = snapshot.seedImported
        self.swiftDataMirrored = snapshot.swiftDataMirrored
        self.hasAcceptedExploreConsent = snapshot.hasAcceptedExploreConsent
        self.exploreConsentGivenAt = snapshot.exploreConsentGivenAt
        self.reviewPromptShown = snapshot.reviewPromptShown
        self.includeMapInExport = snapshot.includeMapInExport
        self.visibleCategories = snapshot.visibleCategories
        self.customTags = snapshot.customTags
        self.foursquareCallsToday = snapshot.foursquareCallsToday
        self.foursquareCallsTodayDate = snapshot.foursquareCallsTodayDate
        self.aiProviderRaw = snapshot.aiProviderRaw
        self.aiApiKey = snapshot.aiApiKey
        self.aiBaseURL = snapshot.aiBaseURL
        self.aiModelName = snapshot.aiModelName
        self.companionAvatarEmoji = snapshot.companionAvatarEmoji
        self.companionBio = snapshot.companionBio
        self.companionLanguages = snapshot.companionLanguages
        self.companionVisibilityRaw = snapshot.companionVisibilityRaw
        self.displayHandle = snapshot.displayHandle
        self.activeCompanionPosts = snapshot.activeCompanionPosts
        self.hasAcceptedCompanionConsent = snapshot.hasAcceptedCompanionConsent
        self.companionConsentGivenAt = snapshot.companionConsentGivenAt
        self.companionEnabled = snapshot.companionEnabled
        self.companionModuleStrengthRaw = snapshot.companionModuleStrengthRaw
    }

    private static func load(from defaults: UserDefaults) -> Snapshot {
        guard let data = defaults.data(forKey: storageKey) else { return Snapshot() }
        do {
            return try JSONDecoder.iso8601Decoder.decode(Snapshot.self, from: data)
        } catch {
            logger.error("decode error — returning defaults. error=\(String(describing: error), privacy: .public)")
            return Snapshot()
        }
    }

    private func persist() {
        let snapshot = Snapshot(
            preferredCategories: preferredCategories,
            dislikedCategories: dislikedCategories,
            soloTravelStyle: soloTravelStyle,
            maxDistanceKm: maxDistanceKm,
            visitHistory: visitHistory,
            completedExperiences: completedExperiences,
            favoritedExperiences: favoritedExperiences,
            favoritedAt: favoritedAt,
            pendingCheckIns: pendingCheckIns,
            lastSelectedCity: lastSelectedCity,
            hasCompletedOnboarding: hasCompletedOnboarding,
            notificationsEnabled: notificationsEnabled,
            quietHoursStart: quietHoursStart,
            quietHoursEnd: quietHoursEnd,
            seedImported: seedImported,
            swiftDataMirrored: swiftDataMirrored,
            hasAcceptedExploreConsent: hasAcceptedExploreConsent,
            exploreConsentGivenAt: exploreConsentGivenAt,
            reviewPromptShown: reviewPromptShown,
            includeMapInExport: includeMapInExport,
            visibleCategories: visibleCategories,
            customTags: customTags,
            foursquareCallsToday: foursquareCallsToday,
            foursquareCallsTodayDate: foursquareCallsTodayDate,
            aiProviderRaw: aiProviderRaw,
            aiApiKey: aiApiKey,
            aiBaseURL: aiBaseURL,
            aiModelName: aiModelName,
            companionAvatarEmoji: companionAvatarEmoji,
            companionBio: companionBio,
            companionLanguages: companionLanguages,
            companionVisibilityRaw: companionVisibilityRaw,
            displayHandle: displayHandle,
            activeCompanionPosts: activeCompanionPosts,
            hasAcceptedCompanionConsent: hasAcceptedCompanionConsent,
            companionConsentGivenAt: companionConsentGivenAt,
            companionEnabled: companionEnabled,
            companionModuleStrengthRaw: companionModuleStrengthRaw
        )
        do {
            let data = try JSONEncoder.iso8601Encoder.encode(snapshot)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            Self.logger.error("encode error: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Repository wiring (US-009 double-write to SwiftData)

    /// Separate legacy UserDefaults keys written by app v1.0 as plain
    /// `[String]` arrays. v1.1 reads these once, inserts SwiftData rows,
    /// then removes the keys so the migration never reruns.
    private static let legacyCompletedKey = "completedExperienceIds"
    private static let legacyFavoritedKey = "favoriteExperienceIds"

    /// Wire the SwiftData-backed `ExperienceRepository` so subsequent
    /// mutations are mirrored to disk. On the first call, also migrates
    /// any pre-existing data: first reads the v1.0 separate-key arrays
    /// (`completedExperienceIds` / `favoriteExperienceIds`) and inserts
    /// corresponding SwiftData rows, then copies any in-memory state
    /// accumulated since boot. Deletes the old keys so the migration
    /// never reruns.
    @MainActor
    public func attachRepository(_ repository: ExperienceRepository) {
        self.experienceRepository = repository
        if !swiftDataMirrored {
            // Phase 1: migrate v1.0 legacy separate-key arrays.
            let legacyCompleted = defaults.stringArray(forKey: Self.legacyCompletedKey) ?? []
            let legacyFavorited = defaults.stringArray(forKey: Self.legacyFavoritedKey) ?? []

            for id in legacyCompleted where !repository.isCompleted(experienceId: id) {
                repository.recordCompletion(
                    experienceId: id,
                    at: visitHistory[id] ?? Date()
                )
                // Absorb into in-memory set so isCompleted() stays consistent.
                completedExperiences.insert(id)
            }
            for id in legacyFavorited where !repository.isFavorited(experienceId: id) {
                _ = repository.toggleFavorite(
                    experienceId: id,
                    at: favoritedAt[id] ?? Date()
                )
                favoritedExperiences.insert(id)
            }

            // Remove old keys — migration must not run a second time.
            defaults.removeObject(forKey: Self.legacyCompletedKey)
            defaults.removeObject(forKey: Self.legacyFavoritedKey)

            // Phase 2: mirror any in-memory state that arrived after boot
            // but before the repo was wired (e.g. from the v1 snapshot blob).
            for id in completedExperiences where !repository.isCompleted(experienceId: id) {
                repository.recordCompletion(
                    experienceId: id,
                    at: visitHistory[id] ?? Date()
                )
            }
            for id in favoritedExperiences where !repository.isFavorited(experienceId: id) {
                _ = repository.toggleFavorite(
                    experienceId: id,
                    at: favoritedAt[id] ?? Date()
                )
            }

            swiftDataMirrored = true
        }
    }

    // MARK: - Convenience mutations

    /// Records that the user finished an experience, updating completion and visit history.
    public func markCompleted(_ id: String, at date: Date = Date()) {
        completedExperiences.insert(id)
        visitHistory[id] = date
        Task { @MainActor in
            self.experienceRepository?.recordCompletion(experienceId: id, at: date)
            self.requestReviewIfEligible()
        }
    }

    /// Triggers SKStoreReviewController.requestReview() when the user has
    /// completed exactly 3 distinct experiences and hasn't been prompted before.
    /// In DEBUG builds, FF_FORCE_REVIEW_PROMPT=1 bypasses the threshold.
    @MainActor
    private func requestReviewIfEligible() {
        #if DEBUG
        let forced = FeatureFlags.forceReviewPrompt
        #else
        let forced = false
        #endif
        guard !reviewPromptShown || forced else { return }
        guard forced || completedExperiences.count >= 3 else { return }
        reviewPromptShown = true
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    /// Adds or removes an experience from the user's favorites.
    public func toggleFavorite(_ id: String, at date: Date = Date()) {
        let nowFavorited: Bool
        if favoritedExperiences.contains(id) {
            favoritedExperiences.remove(id)
            favoritedAt.removeValue(forKey: id)
            nowFavorited = false
        } else {
            favoritedExperiences.insert(id)
            favoritedAt[id] = date
            nowFavorited = true
        }
        Task { @MainActor [weak self] in
            guard let repo = self?.experienceRepository else { return }
            // Repo's toggleFavorite flips state; we want the repo to
            // match our new in-memory state. Re-toggle if needed.
            let repoState = repo.isFavorited(experienceId: id)
            if repoState != nowFavorited {
                _ = repo.toggleFavorite(experienceId: id, at: date)
            }
        }
    }

    /// Marks the first-run onboarding flow as finished so it won't be shown again.
    public func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    /// Mark the Explore-Here consent sheet as accepted. Idempotent.
    public func acceptExploreConsent() {
        hasAcceptedExploreConsent = true
        if exploreConsentGivenAt == nil {
            exploreConsentGivenAt = Date()
        }
    }

    /// Clear Explore-Here consent so the sheet reappears on next tap (US-037).
    public func revokeExploreConsent() {
        hasAcceptedExploreConsent = false
        exploreConsentGivenAt = nil
    }

    /// Mark the companion safety consent sheet as accepted (US-020). Idempotent.
    public func acceptCompanionConsent() {
        hasAcceptedCompanionConsent = true
        if companionConsentGivenAt == nil {
            companionConsentGivenAt = Date()
        }
    }

    /// US-013: bump the Foursquare-fallback usage counter. Rolls the counter
    /// back to 1 (not 0 — we're recording *this* call) when the stored day
    /// stamp differs from the local-calendar start-of-day for `now`.
    /// Visibility-only — no enforcement is performed here.
    public func incrementFoursquareCallsToday(now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        if let stamped = foursquareCallsTodayDate,
           calendar.startOfDay(for: stamped) == today {
            foursquareCallsToday += 1
        } else {
            foursquareCallsToday = 1
            foursquareCallsTodayDate = today
        }
    }

    /// Auto-clear pending check-ins older than 7 days.
    public func pruneStaleCheckIns(olderThan days: Int = 7) {
        let cutoff = Date().addingTimeInterval(Double(-days) * 86_400)
        for (id, date) in pendingCheckIns where date < cutoff {
            pendingCheckIns.removeValue(forKey: id)
        }
    }

    /// True if current hour is inside the quiet-hours window.
    public var isQuietHours: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        if quietHoursStart > quietHoursEnd {
            return hour >= quietHoursStart || hour < quietHoursEnd
        } else {
            return hour >= quietHoursStart && hour < quietHoursEnd
        }
    }

    /// Read-through to SwiftData when the repository is wired; falls back
    /// to the in-memory set for previews and tests that skip `attachRepository`.
    @MainActor
    public func isFavorited(_ id: String) -> Bool {
        if let repo = experienceRepository { return repo.isFavorited(experienceId: id) }
        return favoritedExperiences.contains(id)
    }

    /// Read-through to SwiftData when the repository is wired; falls back
    /// to the in-memory set for previews and tests that skip `attachRepository`.
    @MainActor
    public func isCompleted(_ id: String) -> Bool {
        if let repo = experienceRepository { return repo.isCompleted(experienceId: id) }
        return completedExperiences.contains(id)
    }

    /// Tracks that the user arrived at an experience but hasn't yet confirmed a check-in.
    public func recordPendingCheckIn(_ id: String, at date: Date = Date()) {
        pendingCheckIns[id] = date
    }

    /// Removes a pending check-in once it has been resolved or dismissed.
    public func clearPendingCheckIn(_ id: String) {
        pendingCheckIns.removeValue(forKey: id)
    }
}

// MARK: - JSON helpers (shared, ISO8601 dates)

extension JSONDecoder {
    static let iso8601Decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    static let iso8601Encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

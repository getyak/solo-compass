import Foundation
import Observation
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
        var lastSelectedCity: String? = nil
        var hasCompletedOnboarding: Bool = false
        var notificationsEnabled: Bool = false
        var quietHoursStart: Int = 22
        var quietHoursEnd: Int = 8
        var seedImported: Bool = false
        var swiftDataMirrored: Bool = false
        var hasAcceptedExploreConsent: Bool = false
        var exploreConsentGivenAt: Date? = nil
        var reviewPromptShown: Bool = false

        enum CodingKeys: String, CodingKey {
            case preferredCategories, dislikedCategories, soloTravelStyle, maxDistanceKm
            case visitHistory, completedExperiences, favoritedExperiences, favoritedAt, pendingCheckIns
            case lastSelectedCity, hasCompletedOnboarding, notificationsEnabled
            case quietHoursStart, quietHoursEnd, seedImported, swiftDataMirrored
            case hasAcceptedExploreConsent, exploreConsentGivenAt, reviewPromptShown
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
            reviewPromptShown: Bool
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
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.preferredCategories = try c.decodeIfPresent([ExperienceCategory].self, forKey: .preferredCategories) ?? []
            self.dislikedCategories = try c.decodeIfPresent([ExperienceCategory].self, forKey: .dislikedCategories) ?? []
            self.soloTravelStyle = try c.decodeIfPresent(SoloTravelStyle.self, forKey: .soloTravelStyle) ?? .explorer
            self.maxDistanceKm = try c.decodeIfPresent(Double.self, forKey: .maxDistanceKm) ?? 5.0
            self.visitHistory = try c.decodeIfPresent([String: Date].self, forKey: .visitHistory) ?? [:]
            self.completedExperiences = try c.decodeIfPresent(Set<String>.self, forKey: .completedExperiences) ?? []
            self.favoritedExperiences = try c.decodeIfPresent(Set<String>.self, forKey: .favoritedExperiences) ?? []
            self.favoritedAt = try c.decodeIfPresent([String: Date].self, forKey: .favoritedAt) ?? [:]
            self.pendingCheckIns = try c.decodeIfPresent([String: Date].self, forKey: .pendingCheckIns) ?? [:]
            self.lastSelectedCity = try c.decodeIfPresent(String.self, forKey: .lastSelectedCity)
            self.hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
            self.notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
            self.quietHoursStart = try c.decodeIfPresent(Int.self, forKey: .quietHoursStart) ?? 22
            self.quietHoursEnd = try c.decodeIfPresent(Int.self, forKey: .quietHoursEnd) ?? 8
            self.seedImported = try c.decodeIfPresent(Bool.self, forKey: .seedImported) ?? false
            self.swiftDataMirrored = try c.decodeIfPresent(Bool.self, forKey: .swiftDataMirrored) ?? false
            self.hasAcceptedExploreConsent = try c.decodeIfPresent(Bool.self, forKey: .hasAcceptedExploreConsent) ?? false
            self.exploreConsentGivenAt = try c.decodeIfPresent(Date.self, forKey: .exploreConsentGivenAt)
            self.reviewPromptShown = try c.decodeIfPresent(Bool.self, forKey: .reviewPromptShown) ?? false
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
    }

    private static func load(from defaults: UserDefaults) -> Snapshot {
        guard let data = defaults.data(forKey: storageKey) else { return Snapshot() }
        do {
            return try JSONDecoder.iso8601Decoder.decode(Snapshot.self, from: data)
        } catch {
            #if DEBUG
            print("[UserPreferences] decode error — returning defaults. error=\(error)")
            #endif
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
            reviewPromptShown: reviewPromptShown
        )
        do {
            let data = try JSONEncoder.iso8601Encoder.encode(snapshot)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            #if DEBUG
            print("[UserPreferences] encode error: \(error)")
            #endif
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

    public func recordPendingCheckIn(_ id: String, at date: Date = Date()) {
        pendingCheckIns[id] = date
    }

    public func clearPendingCheckIn(_ id: String) {
        pendingCheckIns.removeValue(forKey: id)
    }
}

// MARK: - JSON helpers (shared, ISO8601 dates)

extension JSONDecoder {
    static let iso8601Decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let iso8601Encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

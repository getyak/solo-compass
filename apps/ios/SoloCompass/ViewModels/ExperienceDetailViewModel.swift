import Foundation
import Observation

/// State + intent for the experience detail sheet.
///
/// @MainActor isolation ensures aiExplanation and other UI-bound properties
/// are always mutated on the main thread after awaiting async calls.
@MainActor
@Observable
public final class ExperienceDetailViewModel {
    public let experience: Experience

    public var isCompleted: Bool
    public var isFavorited: Bool
    public var aiExplanation: String?
    public var isLoadingAIExplanation: Bool = false
    public var isLoadingWhyItMatters: Bool = false
    public var nearbyExperiences: [Experience] = []
    public var visitCount: Int
    var remoteSoloScore: SoloScore?

    public let experienceService: ExperienceService
    public let aiService: AIService
    private let preferences: UserPreferences
    private let reviewsService: ReviewsService
    private weak var subscriptionService: SubscriptionService?

    /// True when the entitlement grants AI access. Defaults to true when no
    /// subscription service is attached (tests / previews).
    private var isProUser: Bool {
        subscriptionService?.entitlement.isActive ?? true
    }

    /// US-004: gate for the "Ask Solo about this" button. Mirrors the "+" plus
    /// button gate — hidden iff the user is not on the Pro tier AND no local
    /// DeepSeek key is configured. Either Pro entitlement (Edge-routed) OR a
    /// local key is enough to keep the button visible.
    public var canAskSolo: Bool {
        aiService.isProTier || !Secrets.resolvedDeepSeekApiKey.isEmpty
    }

    public init(
        experience: Experience,
        experienceService: ExperienceService,
        aiService: AIService,
        preferences: UserPreferences,
        subscriptionService: SubscriptionService? = nil,
        reviewsService: ReviewsService = .shared
    ) {
        self.experience = experience
        self.experienceService = experienceService
        self.aiService = aiService
        self.preferences = preferences
        self.subscriptionService = subscriptionService
        self.reviewsService = reviewsService
        self.isCompleted = preferences.isCompleted(experience.id)
        self.isFavorited = preferences.isFavorited(experience.id)
        self.visitCount = experience.stats.completionCount
        loadNearby()
    }

    /// Returns the best available SoloScore for display.
    /// Priority: remote backend score > local survey aggregation > seed/AI value.
    public var displaySoloScore: SoloScore {
        if let remote = remoteSoloScore { return remote }
        let repo = experienceService.repo
        guard let agg = repo.aggregatedSoloScore(
            experienceId: experience.id,
            seedOverall: experience.soloScore.overall
        ) else {
            return experience.soloScore
        }
        return SoloScore(
            overall: agg.overall,
            breakdown: experience.soloScore.breakdown,
            hint: experience.soloScore.hint,
            basedOnCount: agg.count
        )
    }

    /// Loads the solo score from the backend, falling back to local on any error.
    public func loadRemoteSoloScore() async {
        let local = displaySoloScore
        remoteSoloScore = try? await reviewsService.fetchSoloScore(
            experienceId: experience.id,
            fallback: local
        )
    }

    /// Count of all completed experiences after the last toggleComplete() call.
    /// Updated synchronously inside toggleComplete so callers can read it immediately.
    public private(set) var completedCount: Int = 0

    public func toggleComplete() {
        if isCompleted {
            preferences.completedExperiences.remove(experience.id)
            preferences.visitHistory.removeValue(forKey: experience.id)
            isCompleted = false
        } else {
            preferences.markCompleted(experience.id)
            experienceService.markCompleted(experience.id)
            visitCount += 1
            isCompleted = true
        }
        completedCount = preferences.completedExperiences.count
    }

    public func toggleFavorite() {
        preferences.toggleFavorite(experience.id)
        isFavorited = preferences.isFavorited(experience.id)
    }

    public func loadAIExplanation() async {
        // US-026: free users see an upgrade teaser rather than the loading spinner.
        guard isProUser else {
            aiExplanation = NSLocalizedString("detail.aiInsight.gated", comment: "Subscribe to unlock AI Insight")
            return
        }
        let isOSM = experience.isFromOpenStreetMap
        // Skip AI for OSM entries that never went through synthesis (the
        // skeleton fallback). They carry no real description, so asking the
        // model to "explain" them only produced hallucinated landmarks. Show
        // nothing rather than a fabricated AI Insight; the "why it matters"
        // section keeps the honest "visit and tell us" prompt.
        if isOSM && !experience.isAIEnriched {
            aiExplanation = nil
            return
        }
        isLoadingAIExplanation = true
        if isOSM { isLoadingWhyItMatters = true }
        defer {
            isLoadingAIExplanation = false
            if isOSM { isLoadingWhyItMatters = false }
        }
        do {
            aiExplanation = try await aiService.explainRecommendation(for: experience)
        } catch {
            aiExplanation = nil
            #if DEBUG
            print("[ExperienceDetailViewModel] loadAIExplanation failed for id=\(experience.id): \(error)")
            #endif
        }
    }

    public func loadNearby() {
        nearbyExperiences = experience.nearbyExperienceIds.compactMap {
            experienceService.getExperience(id: $0)
        }
    }
}

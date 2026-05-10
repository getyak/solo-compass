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
    public var nearbyExperiences: [Experience] = []
    public var visitCount: Int

    private let experienceService: ExperienceService
    private let aiService: AIService
    private let preferences: UserPreferences
    private weak var subscriptionService: SubscriptionService?

    /// True when the entitlement grants AI access. Defaults to true when no
    /// subscription service is attached (tests / previews).
    private var isProUser: Bool {
        subscriptionService?.entitlement.isActive ?? true
    }

    public init(
        experience: Experience,
        experienceService: ExperienceService,
        aiService: AIService,
        preferences: UserPreferences,
        subscriptionService: SubscriptionService? = nil
    ) {
        self.experience = experience
        self.experienceService = experienceService
        self.aiService = aiService
        self.preferences = preferences
        self.subscriptionService = subscriptionService
        self.isCompleted = preferences.isCompleted(experience.id)
        self.isFavorited = preferences.isFavorited(experience.id)
        self.visitCount = experience.stats.completionCount
        loadNearby()
    }

    /// Returns the best available SoloScore for display: aggregated from local
    /// survey responses when any exist, otherwise the seed/AI value.
    /// The aggregation blends the original overall (50%) with local survey mean
    /// (50%) plus a +0.5 recommend boost when ≥50% said "yes".
    public var displaySoloScore: SoloScore {
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
        isLoadingAIExplanation = true
        defer { isLoadingAIExplanation = false }
        do {
            aiExplanation = try await aiService.explainRecommendation(for: experience.id)
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

import Foundation

// MARK: - ExperienceFilter

/// Structured filter derived from natural-language queries.
///
/// Quality dimensions (US-017):
/// - ratingMin: minimum provider rating (0–10) from location.rating
/// - ambianceMin: minimum ambianceFit breakdown score (0–10)
/// - quietness: true = high seatingFriendly + low staffPressure
/// - soloFriendly: true = high soloPatronRatio + high soloPortioning
/// - priceMax: maximum price level (1–4)
///
/// Originally lived alongside the now-removed QueryAgent. Promoted to
/// `Models/` because `MapViewModel` and `VoiceAgentToolRouter` consume
/// the predicate (`matches(_:)`) directly.
public struct ExperienceFilter: Sendable, Equatable {
    public let category: String?
    public let maxDistanceMeters: Double?
    public let openNow: Bool
    public let soloScoreMin: Double?
    public let ratingMin: Double?
    public let ambianceMin: Double?
    public let quietness: Bool
    public let soloFriendly: Bool
    public let priceMax: Double?

    public init(
        category: String? = nil,
        maxDistanceMeters: Double? = nil,
        openNow: Bool = false,
        soloScoreMin: Double? = nil,
        ratingMin: Double? = nil,
        ambianceMin: Double? = nil,
        quietness: Bool = false,
        soloFriendly: Bool = false,
        priceMax: Double? = nil
    ) {
        self.category = category
        self.maxDistanceMeters = maxDistanceMeters
        self.openNow = openNow
        self.soloScoreMin = soloScoreMin
        self.ratingMin = ratingMin
        self.ambianceMin = ambianceMin
        self.quietness = quietness
        self.soloFriendly = soloFriendly
        self.priceMax = priceMax
    }

    /// Returns true when `experience` satisfies all active filter dimensions.
    /// Dimensions with nil / false values are skipped (inactive).
    public func matches(_ experience: Experience) -> Bool {
        if let cat = category, !cat.isEmpty {
            guard experience.category.rawValue == cat else { return false }
        }
        if let rMin = ratingMin {
            guard let rating = experience.location.rating, rating >= rMin else { return false }
        }
        if let priceMax, let price = experience.location.priceLevel {
            guard price <= priceMax else { return false }
        }
        if let score = soloScoreMin {
            guard experience.soloScore.overall >= score else { return false }
        }
        if let ambMin = ambianceMin {
            guard experience.soloScore.breakdown.ambianceFit >= ambMin else { return false }
        }
        // quietness: seatingFriendly ≥ 7 AND staffPressure ≤ 3
        if quietness {
            let bd = experience.soloScore.breakdown
            guard bd.seatingFriendly >= 7.0 && bd.staffPressure <= 3.0 else { return false }
        }
        // soloFriendly: soloPatronRatio ≥ 7 AND soloPortioning ≥ 7
        if soloFriendly {
            let bd = experience.soloScore.breakdown
            guard bd.soloPatronRatio >= 7.0 && bd.soloPortioning >= 7.0 else { return false }
        }
        return true
    }
}

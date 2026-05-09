import Foundation
import SwiftData

/// One row per "user has this experience favorited." `experienceId` is
/// unique because favoriting is a toggle (on/off), not a counter — adding
/// the same id twice should fail at the DB layer rather than silently
/// duplicate, so the repository can rely on uniqueness for predicate
/// queries like `isFavorited(id:)`.
@Model
public final class UserFavoriteRecord {
    @Attribute(.unique) public var experienceId: String
    public var id: UUID
    public var favoritedAt: Date

    public init(id: UUID = UUID(), experienceId: String, favoritedAt: Date = Date()) {
        self.id = id
        self.experienceId = experienceId
        self.favoritedAt = favoritedAt
    }
}

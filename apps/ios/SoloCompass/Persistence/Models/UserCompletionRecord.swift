import Foundation
import SwiftData

/// One row per "user marked this experience as completed". Multiple
/// completions of the same experience id are allowed (re-visiting), so
/// `experienceId` is indexed but not unique. Each row carries its own
/// timestamp so we can derive things like "how many places this week."
@Model
public final class UserCompletionRecord {
    @Attribute(.unique) public var id: UUID
    public var experienceId: String
    public var completedAt: Date

    public init(id: UUID = UUID(), experienceId: String, completedAt: Date = Date()) {
        self.id = id
        self.experienceId = experienceId
        self.completedAt = completedAt
    }
}

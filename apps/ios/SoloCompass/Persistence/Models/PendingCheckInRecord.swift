import Foundation
import SwiftData

/// One row per "geofence fired and we should ask the user 'did you visit?'".
/// `experienceId` is unique because at most one pending check-in per
/// experience makes sense — re-triggering should refresh `triggeredAt`,
/// not create duplicates.
@Model
public final class PendingCheckInRecord {
    @Attribute(.unique) public var experienceId: String
    public var id: UUID
    public var triggeredAt: Date

    public init(id: UUID = UUID(), experienceId: String, triggeredAt: Date = Date()) {
        self.id = id
        self.experienceId = experienceId
        self.triggeredAt = triggeredAt
    }
}

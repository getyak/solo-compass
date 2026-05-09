import Foundation
import SwiftData

/// One row per micro-survey submission. Stored locally and (in Epic E)
/// synced to Supabase `solo_score_signals` so community averages can
/// improve future Solo Scores.
///
/// `comfort` and `pressure` are 1–5 (1 worst, 5 best). `recommend` is one
/// of "yes" / "depends" / "no". `anonDeviceId` is the same anon UUID used
/// for Supabase auth so server-side aggregation can dedupe.
@Model
public final class MicroSurveyRecord {
    @Attribute(.unique) public var id: UUID
    public var experienceId: String
    public var comfort: Int
    public var pressure: Int
    public var recommend: String
    public var submittedAt: Date
    public var anonDeviceId: String

    public init(
        id: UUID = UUID(),
        experienceId: String,
        comfort: Int,
        pressure: Int,
        recommend: String,
        submittedAt: Date = Date(),
        anonDeviceId: String
    ) {
        self.id = id
        self.experienceId = experienceId
        self.comfort = max(1, min(5, comfort))
        self.pressure = max(1, min(5, pressure))
        self.recommend = recommend
        self.submittedAt = submittedAt
        self.anonDeviceId = anonDeviceId
    }
}

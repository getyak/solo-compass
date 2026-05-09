import Foundation
import SwiftData

/// One row per UTC day. Counters increment when the AI service makes a
/// real network call (cache hits don't count). Used by Epic B US-B5 to
/// enforce daily quotas.
///
/// `date` is day-truncated UTC (00:00:00 on that day) so a simple equality
/// query finds today's row. `synthesisCalls` and `explanationCalls` track
/// the two model-routed paths separately.
@Model
public final class AIUsageRecord {
    @Attribute(.unique) public var date: Date
    public var id: UUID
    public var synthesisCalls: Int
    public var explanationCalls: Int

    public init(
        id: UUID = UUID(),
        date: Date,
        synthesisCalls: Int = 0,
        explanationCalls: Int = 0
    ) {
        self.id = id
        self.date = date
        self.synthesisCalls = synthesisCalls
        self.explanationCalls = explanationCalls
    }

    /// Truncate `date` to UTC midnight so today's row is keyable as a date.
    public static func todayUTC(_ now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.startOfDay(for: now)
    }
}

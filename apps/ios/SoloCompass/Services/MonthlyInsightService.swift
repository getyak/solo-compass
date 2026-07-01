import Foundation
import Observation
import os

/// P3.3 #330: distils the last 30 days of VisitRecord into 2–3 punchy
/// insights + one shareable data card. Ships as a deterministic on-device
/// aggregator; the LLM prompt slot is reserved for follow-up prose.
///
/// The `MonthlyInsightData` payload is consumed by:
/// - `InsightCardView` (#331) — the screenshot-friendly render.
/// - `ProactiveNudgeScheduler` (P2.6) — pushed on the 1st of each month.
///
/// Determinism: same visit sequence always produces the same insights.
@MainActor
@Observable
public final class MonthlyInsightService {

    public static let shared = MonthlyInsightService()

    private let log = OSLog(subsystem: "com.solocompass.app", category: "MonthlyInsight")

    public init() {}

    /// Compose an insight for the month containing `date`. If `visits`
    /// spans multiple months, we slice to the anchor month first.
    public func compose(
        for date: Date = Date(),
        visits: [VisitRecord],
        experiences: [Experience] = [],
        calendar: Calendar = Calendar.current
    ) -> MonthlyInsightData {
        let (start, end) = Self.monthBounds(for: date, calendar: calendar)
        let scoped = visits.filter { $0.visitedAt >= start && $0.visitedAt < end }

        let topCategory = Self.topCategory(visits: scoped, experiences: experiences)
        let uniqueCityCount = Set(experiences
            .filter { exp in scoped.contains { $0.experienceId == exp.id } }
            .map { $0.location.cityCode }
        ).count

        let dominantHourBand = Self.dominantHourBand(visits: scoped, calendar: calendar)

        let insights = Self.insightLines(
            visitCount: scoped.count,
            topCategory: topCategory,
            uniqueCityCount: uniqueCityCount,
            dominantHourBand: dominantHourBand
        )

        return MonthlyInsightData(
            monthStart: start,
            visitCount: scoped.count,
            uniqueExperienceCount: Set(scoped.map { $0.experienceId }).count,
            uniqueCityCount: uniqueCityCount,
            topCategory: topCategory,
            dominantHourBand: dominantHourBand,
            insights: insights,
            createdAt: Date()
        )
    }

    // MARK: - Helpers

    static func monthBounds(for date: Date, calendar: Calendar) -> (Date, Date) {
        let interval = calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 0)
        return (interval.start, interval.end)
    }

    static func topCategory(
        visits: [VisitRecord],
        experiences: [Experience]
    ) -> String? {
        var counts: [String: Int] = [:]
        for v in visits {
            guard let exp = experiences.first(where: { $0.id == v.experienceId }) else { continue }
            counts[exp.category.rawValue, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key
    }

    static func dominantHourBand(
        visits: [VisitRecord],
        calendar: Calendar
    ) -> String {
        guard !visits.isEmpty else { return "unknown" }
        var counts: [String: Int] = [:]
        for v in visits {
            let hour = calendar.component(.hour, from: v.visitedAt)
            let band: String
            switch hour {
            case 5..<11: band = "morning"
            case 11..<17: band = "afternoon"
            case 17..<21: band = "evening"
            default: band = "night"
            }
            counts[band, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key ?? "unknown"
    }

    static func insightLines(
        visitCount: Int,
        topCategory: String?,
        uniqueCityCount: Int,
        dominantHourBand: String
    ) -> [String] {
        var lines: [String] = []
        if visitCount == 0 {
            lines.append("Quiet month. No visits logged.")
            return lines
        }
        lines.append("You logged \(visitCount) places this month.")
        if let topCategory {
            lines.append("Your gravity: \(topCategory).")
        }
        if uniqueCityCount > 1 {
            lines.append("\(uniqueCityCount) cities. You wandered.")
        }
        lines.append("Your time of day was \(dominantHourBand).")
        return lines
    }
}

/// P3.3 #330 payload.
public struct MonthlyInsightData: Codable, Hashable, Sendable {
    public let monthStart: Date
    public let visitCount: Int
    public let uniqueExperienceCount: Int
    public let uniqueCityCount: Int
    public let topCategory: String?
    public let dominantHourBand: String
    public let insights: [String]
    public let createdAt: Date
}

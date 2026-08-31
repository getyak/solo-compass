import Foundation
import os
import Observation

/// Tracks user interaction signals with experiences for future ranking model training.
/// Phase 1: in-memory + os.Logger. Phase 2: SwiftData persistence + Supabase sync.
@MainActor
@Observable
public final class InteractionTracker {

    /// User-perceived latency journeys with explicit product budgets. These are
    /// local performance measurements (os_signpost + an in-memory rolling
    /// window), not behavioral analytics, so they can be inspected in
    /// Instruments without uploading location or interaction data.
    public enum LatencyJourney: String, CaseIterable {
        case pinToDetail = "pin_to_detail"
        case sheetSettle = "sheet_settle"

        /// p95 product budget in milliseconds. A tap should acknowledge within
        /// 100 ms; the complete warm detail surface gets a slightly wider 300 ms
        /// budget because SwiftUI still has to present and lay out the sheet.
        public var budgetMilliseconds: Double {
            switch self {
            case .pinToDetail: return 300
            case .sheetSettle: return 400
            }
        }
    }

    /// One completed latency measurement retained in the rolling session window.
    public struct LatencySample: Equatable {
        public let journey: LatencyJourney
        public let durationMilliseconds: Double
        public let withinBudget: Bool
    }

    /// Distribution summary for one user journey. Percentiles are calculated
    /// from the bounded in-memory window, so this is a session diagnostic—not
    /// a cross-user analytics claim.
    public struct LatencySummary: Equatable {
        public let journey: LatencyJourney
        public let sampleCount: Int
        public let p50Milliseconds: Double
        public let p95Milliseconds: Double
        public let withinBudgetRate: Double
        public let budgetMilliseconds: Double

        public var isWithinBudget: Bool {
            p95Milliseconds <= budgetMilliseconds
        }
    }

    private struct PendingLatency {
        let startedAtUptime: TimeInterval
        let signpostID: OSSignpostID
    }

    public enum EventType: String, Codable {
        case pinTap = "pin_tap"
        case detailOpen = "detail_open"
        case detailDwell = "detail_dwell"
        case saveToFavorites = "save_favorite"
        case removeFavorite = "remove_favorite"
        case routeAdd = "route_add"
        case routeStart = "route_start"
        case dismissRecommendation = "dismiss"
        case chatMention = "chat_mention"
        case exploreNearby = "explore_nearby"
    }

    public struct InteractionEvent: Codable {
        public let type: EventType
        public let experienceId: String?
        public let category: String?
        public let timestamp: Date
        public let metadata: [String: String]

        public init(
            type: EventType,
            experienceId: String? = nil,
            category: String? = nil,
            metadata: [String: String] = [:]
        ) {
            self.type = type
            self.experienceId = experienceId
            self.category = category
            self.timestamp = Date()
            self.metadata = metadata
        }
    }

    public static let shared = InteractionTracker()

    public private(set) var sessionEvents: [InteractionEvent] = []

    /// Rolling local diagnostic window. Keeping this bounded avoids turning
    /// instrumentation into its own memory-growth problem during long trips.
    public private(set) var latencySamples: [LatencySample] = []

    private static let logger = Logger(subsystem: "com.solocompass", category: "InteractionTracker")
    private static let performanceLog = OSLog(
        subsystem: "com.solocompass",
        category: .pointsOfInterest
    )
    @ObservationIgnored private var pendingLatencies: [String: PendingLatency] = [:]
    private static let latencySampleLimit = 100

    private init() {}

    public func track(_ type: EventType, experienceId: String? = nil, category: String? = nil, metadata: [String: String] = [:]) {
        let event = InteractionEvent(type: type, experienceId: experienceId, category: category, metadata: metadata)
        sessionEvents.append(event)
        Self.logger.info("interaction: \(type.rawValue, privacy: .public) exp=\(experienceId ?? "-", privacy: .public) cat=\(category ?? "-", privacy: .public)")
    }

    /// Starts a user-perceived latency journey immediately at the input edge.
    /// Reusing the same `(journey, experience)` key replaces a stale pending
    /// sample, which makes rapid double taps deterministic instead of pairing
    /// the final render with an arbitrarily old tap.
    public func beginLatency(_ journey: LatencyJourney, experienceId: String? = nil) {
        let key = latencyKey(journey, experienceId: experienceId)
        let signpostID = OSSignpostID(log: Self.performanceLog)
        pendingLatencies[key] = PendingLatency(
            startedAtUptime: ProcessInfo.processInfo.systemUptime,
            signpostID: signpostID
        )
        os_signpost(
            .begin,
            log: Self.performanceLog,
            name: "UX latency",
            signpostID: signpostID,
            "journey=%{public}s",
            journey.rawValue
        )
    }

    /// Finishes a journey at the first usable frame and returns its duration.
    /// `nil` means no matching input edge was recorded (for example a detail
    /// view opened from state restoration rather than a fresh tap).
    @discardableResult
    public func finishLatency(_ journey: LatencyJourney, experienceId: String? = nil) -> Double? {
        let key = latencyKey(journey, experienceId: experienceId)
        guard let pending = pendingLatencies.removeValue(forKey: key) else { return nil }

        let duration = max(
            0,
            (ProcessInfo.processInfo.systemUptime - pending.startedAtUptime) * 1_000
        )
        let withinBudget = duration <= journey.budgetMilliseconds
        recordLatencySample(LatencySample(
            journey: journey,
            durationMilliseconds: duration,
            withinBudget: withinBudget
        ))

        os_signpost(
            .end,
            log: Self.performanceLog,
            name: "UX latency",
            signpostID: pending.signpostID,
            "journey=%{public}s duration_ms=%.2f budget_ms=%.0f within_budget=%{public}s",
            journey.rawValue,
            duration,
            journey.budgetMilliseconds,
            withinBudget ? "true" : "false"
        )
        return duration
    }

    /// Session-local p50/p95 and budget pass rate for a developer diagnostic
    /// surface. The linear percentile interpolation remains deterministic for
    /// small samples while converging on the usual percentile definition as
    /// the 100-sample window fills.
    public func latencySummary(for journey: LatencyJourney) -> LatencySummary? {
        Self.latencySummary(for: journey, samples: latencySamples)
    }

    static func latencySummary(
        for journey: LatencyJourney,
        samples: [LatencySample]
    ) -> LatencySummary? {
        let relevant = samples
            .filter { $0.journey == journey }
            .sorted { $0.durationMilliseconds < $1.durationMilliseconds }
        guard !relevant.isEmpty else { return nil }

        let durations = relevant.map(\.durationMilliseconds)
        let withinBudgetCount = relevant.lazy.filter(\.withinBudget).count
        return LatencySummary(
            journey: journey,
            sampleCount: relevant.count,
            p50Milliseconds: percentile(0.50, in: durations),
            p95Milliseconds: percentile(0.95, in: durations),
            withinBudgetRate: Double(withinBudgetCount) / Double(relevant.count),
            budgetMilliseconds: journey.budgetMilliseconds
        )
    }

    /// Developer-only diagnostics remain ephemeral and user-controlled.
    public func clearLatencySamples() {
        latencySamples.removeAll(keepingCapacity: true)
    }

    private func recordLatencySample(_ sample: LatencySample) {
        latencySamples.append(sample)
        if latencySamples.count > Self.latencySampleLimit {
            latencySamples.removeFirst(latencySamples.count - Self.latencySampleLimit)
        }
    }

    private static func percentile(_ percentile: Double, in sortedValues: [Double]) -> Double {
        guard let first = sortedValues.first else { return 0 }
        guard sortedValues.count > 1 else { return first }
        let position = percentile * Double(sortedValues.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        guard lowerIndex != upperIndex else { return sortedValues[lowerIndex] }
        let fraction = position - Double(lowerIndex)
        return sortedValues[lowerIndex]
            + (sortedValues[upperIndex] - sortedValues[lowerIndex]) * fraction
    }

    private func latencyKey(_ journey: LatencyJourney, experienceId: String?) -> String {
        "\(journey.rawValue):\(experienceId ?? "-")"
    }

    /// Session summary for analytics — counts by event type.
    public var sessionSummary: [EventType: Int] {
        Dictionary(grouping: sessionEvents, by: \.type).mapValues(\.count)
    }
}

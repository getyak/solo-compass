import Foundation
import os
import Observation

/// Tracks user interaction signals with experiences for future ranking model training.
/// Phase 1: in-memory + os.Logger. Phase 2: SwiftData persistence + Supabase sync.
@MainActor
@Observable
public final class InteractionTracker {

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

    private static let logger = Logger(subsystem: "com.solocompass", category: "InteractionTracker")

    private init() {}

    public func track(_ type: EventType, experienceId: String? = nil, category: String? = nil, metadata: [String: String] = [:]) {
        let event = InteractionEvent(type: type, experienceId: experienceId, category: category, metadata: metadata)
        sessionEvents.append(event)
        Self.logger.info("interaction: \(type.rawValue, privacy: .public) exp=\(experienceId ?? "-", privacy: .public) cat=\(category ?? "-", privacy: .public)")
    }

    /// Session summary for analytics — counts by event type.
    public var sessionSummary: [EventType: Int] {
        Dictionary(grouping: sessionEvents, by: \.type).mapValues(\.count)
    }
}

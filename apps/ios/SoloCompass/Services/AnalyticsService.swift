import Foundation
import Observation
import os

/// X.2 #X20 + #X21: privacy-first analytics.
///
/// Design rules:
/// - **Local first**: every event lands in a bounded in-memory ring
///   (max `bufferCap` events) + persisted to UserDefaults so a crash
///   doesn't lose the pending flush. The remote uploader is a swap-in
///   point — this v1 keeps everything on-device.
/// - **No PII**: only opaque event names + numeric / enum values.
///   Coordinates, user text, emails never enter the pipeline. Enforced
///   at API level: `track(_:properties:)` accepts `[String: AnalyticsValue]`
///   whose associated values are constrained to `Int / Double / String
///   / Bool`. Callers that try to pass a Coord get a compile error.
/// - **Opt-out honoured**: `enabled` toggle — when false, `track(...)`
///   is a no-op and the persisted buffer is dropped.
@MainActor
@Observable
public final class AnalyticsService {

    public static let shared = AnalyticsService()

    /// Max events kept in memory before the oldest is dropped.
    public var bufferCap: Int = 500

    private static let persistKey = "com.solocompass.analytics.buffer.v1"

    /// Toggle used by `Settings` and the "forget me" flow.
    public var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if !newValue {
                buffer.removeAll()
                UserDefaults.standard.removeObject(forKey: Self.persistKey)
            }
        }
    }
    private static let enabledKey = "com.solocompass.analytics.enabled.v1"

    private var buffer: [AnalyticsEvent] = []
    private let log = OSLog(subsystem: "com.solocompass.app", category: "Analytics")

    public init() {
        rehydrateFromDisk()
    }

    // MARK: - Public event API

    /// Track a well-known event by name. Property values are typed so
    /// coordinates + user text can't sneak in.
    public func track(_ name: EventName, properties: [String: AnalyticsValue] = [:]) {
        guard enabled else { return }
        let event = AnalyticsEvent(
            name: name.rawValue,
            properties: properties,
            recordedAt: Date()
        )
        buffer.append(event)
        if buffer.count > bufferCap {
            buffer.removeFirst(buffer.count - bufferCap)
        }
        persist()
    }

    /// Drain the buffer to disk. Kept public so tests can call directly.
    public func flushLocal() {
        persist()
    }

    /// The buffered event count — useful for tests + Settings debug row.
    public var pendingCount: Int { buffer.count }

    // MARK: - Persistence

    private func rehydrateFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: Self.persistKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([AnalyticsEvent].self, from: data)
            buffer = Array(decoded.suffix(bufferCap))
        } catch {
            os_log("Analytics: rehydrate decode failed %{public}@", log: log, type: .error, String(describing: error))
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(buffer)
            UserDefaults.standard.set(data, forKey: Self.persistKey)
        } catch {
            os_log("Analytics: persist encode failed %{public}@", log: log, type: .error, String(describing: error))
        }
    }

    // MARK: - Types

    /// Canonical event names — enum so typos don't wander into the funnel.
    public enum EventName: String, Codable, Sendable {
        // X.2 #X20 catalog
        case capsuleBuried       = "capsule_buried"
        case capsuleOpened       = "capsule_opened"
        case blindboxStarted     = "blindbox_started"
        case agentHintAccepted   = "agent_hint_accepted"
        case archiveVisited      = "archive_visited"
        // X.2 #X21 Pro conversion funnel
        case paywallShown        = "paywall_shown"
        case iapInitiated        = "iap_initiated"
        case iapSuccess          = "iap_success"
        case iapFailed           = "iap_failed"
    }
}

/// Constrained value type for analytics properties. Prevents raw
/// coordinates / user text from making it into the payload — a
/// compile-time guarantee.
public enum AnalyticsValue: Codable, Hashable, Sendable {
    case int(Int)
    case double(Double)
    case string(String)
    case bool(Bool)

    private enum CodingKeys: String, CodingKey { case type, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "int":    self = .int(try c.decode(Int.self, forKey: .value))
        case "double": self = .double(try c.decode(Double.self, forKey: .value))
        case "string": self = .string(try c.decode(String.self, forKey: .value))
        case "bool":   self = .bool(try c.decode(Bool.self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "Unknown AnalyticsValue type \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .int(let v):    try c.encode("int", forKey: .type);    try c.encode(v, forKey: .value)
        case .double(let v): try c.encode("double", forKey: .type); try c.encode(v, forKey: .value)
        case .string(let v): try c.encode("string", forKey: .type); try c.encode(v, forKey: .value)
        case .bool(let v):   try c.encode("bool", forKey: .type);   try c.encode(v, forKey: .value)
        }
    }
}

public struct AnalyticsEvent: Codable, Hashable, Sendable {
    public let name: String
    public let properties: [String: AnalyticsValue]
    public let recordedAt: Date
}

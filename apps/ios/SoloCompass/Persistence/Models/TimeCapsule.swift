import Foundation
import SwiftData

/// One row per "time capsule the user buried at an experience." A capsule is
/// a message-to-future-self: text / voice / photo content, plus a snapshot of
/// the surrounding moment (weather, taste profile, mood), scheduled to surface
/// when the user re-enters the ±500m region after `scheduledFor`.
///
/// This is the v1.0 lock-in feature. The longer a user has used the app, the
/// more capsules ripen — and unsubscribing means missing the future surprises
/// they've already invested in burying. So this table grows but never gets
/// auto-pruned; deletion is an explicit user action only.
///
/// `scheduledFor` is queried frequently (every app launch + every region
/// enter) to find ripe capsules. SwiftData doesn't expose an explicit index
/// API on this version's @Model attributes, so callers rely on the predicate
/// `#Predicate<TimeCapsule> { !$0.opened && $0.scheduledFor <= now }` and
/// trust SwiftData's underlying SQLite to range-scan efficiently against the
/// small row count expected per user.
///
/// Created by CapsuleComposeView (P2.4 #241), read+surfaced by
/// VisitTrackingService (region matcher) + LiveActivityService
/// (`startTimeCapsule`, P2.2 #223), opened by CapsuleOpenView (P2.4 #242).
@Model
public final class TimeCapsule {
    @Attribute(.unique) public var id: UUID
    public var experienceId: String
    public var createdAt: Date
    /// When the capsule becomes eligible to surface. Until this date passes,
    /// the capsule is hidden even if the user enters the region.
    public var scheduledFor: Date
    /// One of `"text"`, `"voice"`, `"photo"`. Codified as String (not enum)
    /// to keep the schema stable across model-set evolution — adding a new
    /// content type just means accepting a new String value in the codec,
    /// no schema migration needed.
    public var contentType: String
    /// The capsule payload. Encoding depends on `contentType`:
    /// - text:  UTF-8 of the message
    /// - voice: AAC/M4A audio bytes (kept short: voice notes ≤ 60s)
    /// - photo: HEIC bytes (downscaled at compose time to ≤ 1 MP)
    public var contentBlob: Data
    /// Optional JSON-encoded `CapsuleContext` (weatherCode, taste descriptors
    /// snapshot, moodEmoji). Optional because the compose step may skip
    /// context to keep the bury flow under 10 seconds.
    public var contextBlob: Data?
    /// Has the user actually opened this capsule yet? Flipped to `true` by
    /// CapsuleOpenView after the unwrap animation completes. Filter on
    /// `!opened` to find still-buried capsules.
    public var opened: Bool

    public init(
        id: UUID = UUID(),
        experienceId: String,
        createdAt: Date = Date(),
        scheduledFor: Date,
        contentType: String,
        contentBlob: Data,
        contextBlob: Data? = nil,
        opened: Bool = false
    ) {
        self.id = id
        self.experienceId = experienceId
        self.createdAt = createdAt
        self.scheduledFor = scheduledFor
        self.contentType = contentType
        self.contentBlob = contentBlob
        self.contextBlob = contextBlob
        self.opened = opened
    }

    /// Recognised content-type tokens. `String`-backed rather than nested
    /// `enum` on the @Model so adding a new media type is purely additive.
    public enum ContentType {
        public static let text = "text"
        public static let voice = "voice"
        public static let photo = "photo"
    }
}

/// JSON-codable companion holding the moment-of-burial context. Stored as
/// a `Data?` blob on `TimeCapsule.contextBlob` so we can evolve it (add
/// fields, drop fields) without bumping the SwiftData schema version.
public struct CapsuleContext: Codable, Hashable, Sendable {
    /// Weather token at burial time, e.g. "clear", "rain". Mirrors
    /// `VisitRecord.weatherCode` vocabulary.
    public var weatherCode: String?
    /// Snapshot of `TasteProfile.descriptors` at burial — surfaced on open so
    /// the user can see "you were into 'quiet/sunlit' back then."
    public var tasteDescriptors: [String]?
    /// Optional 1-character emoji the user picked for the moment.
    public var moodEmoji: String?

    public init(
        weatherCode: String? = nil,
        tasteDescriptors: [String]? = nil,
        moodEmoji: String? = nil
    ) {
        self.weatherCode = weatherCode
        self.tasteDescriptors = tasteDescriptors
        self.moodEmoji = moodEmoji
    }

    /// Encode this context for `TimeCapsule.contextBlob`. Returns `nil` if
    /// every field is `nil` (no point persisting an empty blob).
    public func encoded() throws -> Data? {
        if weatherCode == nil && tasteDescriptors == nil && moodEmoji == nil {
            return nil
        }
        return try JSONEncoder().encode(self)
    }

    /// Decode from a `TimeCapsule.contextBlob`. Returns `nil` on missing or
    /// malformed blob so callers can show "no context recorded" instead of
    /// crashing on a stale capsule from a removed schema version.
    public static func decode(from data: Data?) -> CapsuleContext? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(CapsuleContext.self, from: data)
    }
}

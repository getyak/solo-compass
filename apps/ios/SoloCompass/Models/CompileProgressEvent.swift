import Foundation

/// One line in the deep cross-compile feed. The recompile pipeline is an AI
/// agent loop that fans out across several POI providers, ranks, backfills, and
/// synthesizes — but until now all of that ran behind a single spinner, so a
/// tap that found nothing looked identical to a tap that was still working.
///
/// A `CompileProgressEvent` makes each stage of that loop *visible*: which
/// source is being queried, how many signals it returned, whether it succeeded,
/// was skipped (no key / not applicable), or failed. The feed sheet renders
/// these in order, so the user watches the agent think instead of staring at a
/// spinner that may or may not resolve.
public struct CompileProgressEvent: Identifiable, Equatable, Sendable {
    /// The distinct stages of the enrichment loop, in pipeline order. Used to
    /// pick an icon and a human label; the `detail` string carries specifics.
    public enum Stage: String, Sendable {
        case start            // "Deep cross-compile started"
        case amap             // Amap POIs (mainland China authoritative)
        case mapKit           // Apple MapKit POIs
        case overpass         // OpenStreetMap / Overpass
        case foursquare       // Foursquare hard signals (rating/hours/price)
        case ranking          // Signal-richness ranking, top-N cut
        case address          // Reverse-geocode street-address backfill
        case synthesis        // AI synthesis of the enriched, ranked POIs
        case webVerify        // Web-search verification of objective fields
        case adopt            // Quality/identity gate before replacing the card
        case done             // Terminal success
        case failed           // Terminal failure / no upgrade found
    }

    /// How a stage resolved. Drives the row's color and glyph in the feed:
    /// running = spinner, success = green ✓, skipped = muted dash, failure = red ✗.
    public enum Status: String, Sendable {
        case running
        case success
        case skipped
        case failure
    }

    public let id: UUID
    public let stage: Stage
    public var status: Status
    /// Human-readable specifics for this line — a count, a provider name, or a
    /// reason for a skip/failure. Kept short; the stage supplies the verb.
    public var detail: String

    public init(
        id: UUID = UUID(),
        stage: Stage,
        status: Status,
        detail: String = ""
    ) {
        self.id = id
        self.stage = stage
        self.status = status
        self.detail = detail
    }
}

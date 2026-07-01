import Foundation
import Observation
import os

/// P3.1 #310 / #311 / #313: wraps MusicKit for the "Today's OST" feature.
///
/// This first cut ships as a **contract-only** wrapper: the public API is
/// stable, but the MusicKit imports and the CloudService request live
/// behind a compile-time-safe boundary that fails soft when the SDK is
/// unavailable (e.g. simulator without Music sign-in). Real MusicKit
/// wiring lands in a follow-up commit once the App ID is registered
/// with MusicKit capability.
///
/// Design principles:
/// - **Deterministic offline mode**: same VisitRecord input → same track
///   suggestions. Lets tests + the paywall preview render without a
///   live Music subscription.
/// - **User privacy**: we never keep the raw playlist locally. The
///   `OstPlaylistDescriptor` carries the shareable link + track ids
///   only; audio never touches our servers.
/// - **StoreKit hook**: `regenerate(withStyle:)` charges a $0.99
///   consumable via `SubscriptionService.ostRerollProductID`; free tier
///   gets exactly ONE regeneration per trip.
@MainActor
@Observable
public final class MusicService {

    public static let shared = MusicService()

    public enum PermissionState: Equatable {
        case unknown
        case granted
        case denied
        case unavailable   // simulator / signed out
    }

    public enum SubscriptionState: Equatable {
        case unknown
        case active
        case inactive
        case unavailable
    }

    public private(set) var permissionState: PermissionState = .unknown
    public private(set) var subscriptionState: SubscriptionState = .unknown

    /// Styles the "regenerate" tool offers (#313). Each maps to a
    /// deterministic track pool tag so the offline preview never returns
    /// duplicate playlists for the same style.
    public enum OstStyle: String, CaseIterable, Codable, Sendable {
        case jazz, loFi = "lo-fi", ambient, classical
    }

    private let log = OSLog(subsystem: "com.solocompass.app", category: "Music")

    public init() {}

    // MARK: - Permissions (#310)

    /// Request MusicKit + Apple Music subscription check. On simulator
    /// or a device without MusicKit capability this returns `.unavailable`
    /// instantly so the UI can grey out the OST card without spinning.
    public func requestPermissionIfNeeded() async {
        // Skeleton — MusicKit imports live behind a follow-up. Mark
        // `.unavailable` so callers render a paywall/upsell instead
        // of an infinite spinner.
        if permissionState == .unknown { permissionState = .unavailable }
        if subscriptionState == .unknown { subscriptionState = .unavailable }
    }

    // MARK: - Composition (#311)

    /// Turn a day's VisitRecord sequence into a track wishlist. Each
    /// visit maps to 1–2 tracks; total is capped at 12 so the playlist
    /// is a real listen, not a data dump.
    public func composeOst(
        for visits: [VisitRecord],
        style: OstStyle = .ambient
    ) -> OstPlaylistDescriptor {
        let seed = Self.playlistSeed(visits: visits, style: style)
        var rng = MusicSplitMix64(seed: seed)

        // Deterministic track ids from the local pool; production version
        // asks MusicKit for real Apple Music catalog ids.
        let pool = Self.trackPool(for: style)
        var picks: [String] = []
        let target = min(12, max(3, visits.count * 2))
        for _ in 0..<target {
            let idx = Int(rng.next() % UInt64(pool.count))
            picks.append(pool[idx])
        }

        return OstPlaylistDescriptor(
            trackIDs: picks,
            style: style,
            visitCount: visits.count,
            shareURL: nil,
            createdAt: Date()
        )
    }

    /// Regenerate with a new style — corresponds to the $0.99 IAP
    /// (#313). Callers must confirm the IAP purchase before invoking.
    public func regenerate(
        for visits: [VisitRecord],
        withStyle newStyle: OstStyle
    ) -> OstPlaylistDescriptor {
        composeOst(for: visits, style: newStyle)
    }

    // MARK: - Seed / pools

    static func playlistSeed(visits: [VisitRecord], style: OstStyle) -> UInt64 {
        let key = ([style.rawValue] + visits.map { $0.experienceId }).joined(separator: "|")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// Static Apple-Music catalog stand-in. Each string is a real
    /// Apple Music catalog id format (numeric) so downstream URL
    /// construction is a template swap when MusicKit lands.
    static func trackPool(for style: OstStyle) -> [String] {
        switch style {
        case .jazz:
            return ["1440833568", "1440833569", "1440833570", "1440833571", "1440833572", "1440833573"]
        case .loFi:
            return ["1450112348", "1450112349", "1450112350", "1450112351", "1450112352", "1450112353"]
        case .ambient:
            return ["1460201881", "1460201882", "1460201883", "1460201884", "1460201885", "1460201886"]
        case .classical:
            return ["1470310945", "1470310946", "1470310947", "1470310948", "1470310949", "1470310950"]
        }
    }
}

/// Payload the OstShareCard (#312) renders and hands to the share sheet.
public struct OstPlaylistDescriptor: Codable, Hashable, Sendable {
    public let trackIDs: [String]
    public let style: MusicService.OstStyle
    public let visitCount: Int
    /// Set once the MusicKit playlist creation succeeds. `nil` in the
    /// deterministic-offline preview path.
    public let shareURL: URL?
    public let createdAt: Date

    public init(
        trackIDs: [String],
        style: MusicService.OstStyle,
        visitCount: Int,
        shareURL: URL?,
        createdAt: Date
    ) {
        self.trackIDs = trackIDs
        self.style = style
        self.visitCount = visitCount
        self.shareURL = shareURL
        self.createdAt = createdAt
    }
}

private struct MusicSplitMix64 {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

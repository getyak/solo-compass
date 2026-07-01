import Foundation
import SwiftData

/// Singleton model — one row per user, carrying a compact summary of the
/// user's long-running context (cities visited, recent obsessions, current
/// trip arc) that the Solo Agent injects into every new chat session's system
/// prompt. The goal: agent feels like it "knows you" without sending the
/// whole chat history back over the LLM context window on every turn.
///
/// Singleton semantics are enforced at the store layer, same pattern as
/// `TasteProfile` — the agent memory store deletes any prior row in the
/// same transaction before inserting the new one. The dedicated `id` UUID
/// keeps SwiftData happy (every @Model needs a unique key) without
/// pretending there's more than one row.
///
/// Every field except `id` and `updatedAt` is on-device generated content
/// — never cloud-synced — so a user can fully clear this with the
/// "forget me" button (P2.0 #204).
///
/// Created/updated by MemoryDigestService (P2.0 #202, new). Each chat
/// session's exit triggers an async LLM digest that updates `summary` and
/// `recentChatDigest`; `lastTripCity` flips when a new CompassMapView trip
/// session is detected.
@Model
public final class AgentMemorySnapshot {
    @Attribute(.unique) public var id: UUID
    /// Long-running compact summary of the user, ≤500 characters. Things
    /// like "Solo traveler, loves quiet sunlit cafes, currently in Bangkok
    /// for 6 days, fell in love with one specific spot." Hand-tuned format
    /// dictated by the LLM digest prompt — store layer doesn't parse.
    public var summary: String
    /// The city of the user's most recent (or currently active) trip. Used
    /// to keep "your last trip was…" coherent in cold-open prompts. Nil if
    /// the user hasn't yet completed a trip arc.
    public var lastTripCity: String?
    /// Compact digest of the most recent ~7 days of chat, ≤300 characters.
    /// Lets the agent reference recent conversation ("you asked about
    /// markets twice this week") without re-loading raw messages.
    public var recentChatDigest: String
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        summary: String = "",
        lastTripCity: String? = nil,
        recentChatDigest: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.summary = summary
        self.lastTripCity = lastTripCity
        self.recentChatDigest = recentChatDigest
        self.updatedAt = updatedAt
    }

    /// Render this snapshot as a single block of text suitable for injecting
    /// into a chat system prompt. Empty fields are skipped so a cold-start
    /// user gets no "summary: [empty]" noise in their prompt.
    public func systemPromptBlock() -> String {
        var lines: [String] = []
        if !summary.isEmpty {
            lines.append("About this user: \(summary)")
        }
        if let lastTripCity, !lastTripCity.isEmpty {
            lines.append("Last/current trip: \(lastTripCity)")
        }
        if !recentChatDigest.isEmpty {
            lines.append("Recent chats: \(recentChatDigest)")
        }
        return lines.joined(separator: "\n")
    }
}

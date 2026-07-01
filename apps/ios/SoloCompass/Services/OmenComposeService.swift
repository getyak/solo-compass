import Foundation
import Observation
import os

/// P3.0 #301: composes the daily "city omen" — one line + one micro-task +
/// one anchor experience, refreshed once per local day at 7am.
///
/// Design constraints:
/// - **Tone**: dry, Co-Star-adjacent. Never cute. The deterministic
///   fallback keeps the voice consistent even without an LLM.
/// - **Determinism per day**: same date + same taste profile → same
///   omen, so a user swiping away the notification and re-opening the
///   app doesn't see it change. Key is `date(yyyy-MM-dd) × taste`.
/// - **On-device first**: LLM call is an optional enrichment. The
///   default `compose(for:...)` returns a deterministic omen without
///   any network. The `setUseLLM(true)` flag is reserved for the day
///   the AIService prompt lands.
@MainActor
@Observable
public final class OmenComposeService {

    public static let shared = OmenComposeService()

    public private(set) var useLLM: Bool = false
    public func setUseLLM(_ flag: Bool) { self.useLLM = flag }

    private let log = OSLog(subsystem: "com.solocompass.app", category: "Omen")

    public init() {}

    // MARK: - Public API

    /// Compose today's omen. Deterministic per (date, tasteDescriptors).
    public func compose(
        for date: Date = Date(),
        tasteDescriptors: [String] = [],
        anchorCandidates: [Experience] = [],
        calendar: Calendar = Calendar.current
    ) -> OmenCardData {
        let seed = Self.dailySeed(for: date, tasteDescriptors: tasteDescriptors, calendar: calendar)
        var rng = OmenSplitMix64(seed: seed)

        let lineIndex = Int(rng.next() % UInt64(Self.omenLines.count))
        let taskIndex = Int(rng.next() % UInt64(Self.microTasks.count))
        let line = Self.omenLines[lineIndex]
        let task = Self.microTasks[taskIndex]

        let anchor: Experience?
        if anchorCandidates.isEmpty {
            anchor = nil
        } else {
            let anchorIndex = Int(rng.next() % UInt64(anchorCandidates.count))
            anchor = anchorCandidates[anchorIndex]
        }

        return OmenCardData(
            date: calendar.startOfDay(for: date),
            line: line,
            microTask: task,
            anchorExperienceId: anchor?.id,
            anchorTitle: anchor?.title
        )
    }

    // MARK: - Seed

    /// FNV-1a hash of "YYYY-MM-DD|desc1|desc2…" — stable across launches.
    static func dailySeed(
        for date: Date,
        tasteDescriptors: [String],
        calendar: Calendar
    ) -> UInt64 {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let dateKey = String(format: "%04d-%02d-%02d",
                             components.year ?? 2026,
                             components.month ?? 1,
                             components.day ?? 1)
        let joined = ([dateKey] + tasteDescriptors.sorted()).joined(separator: "|")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in joined.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }

    // MARK: - Content pools

    /// Deterministic omen lines. Deliberately short + declarative — the
    /// user should re-read it, not skim past it.
    static let omenLines: [String] = [
        "Today rewards small detours.",
        "Sit where the light is thin.",
        "You've been ahead of yourself. Pace back a half step.",
        "A stranger will unlock a small door for you.",
        "One conversation is enough today. Choose it.",
        "The place you almost went two weeks ago — go now.",
        "Do the thing that only takes fifteen minutes.",
        "Say the plan out loud once. Then keep it.",
        "Something you thought was closed will be open.",
        "Quiet is a form of luck. Spend it.",
    ]

    /// One-line micro-tasks. Must be completable inside a normal day
    /// with no equipment.
    static let microTasks: [String] = [
        "Order the second cheapest coffee.",
        "Walk one block past where you meant to turn.",
        "Sit in a place you've walked past twice this week.",
        "Send one message you've been drafting.",
        "Photograph a door, not a view.",
        "Ask one honest question of one person.",
        "Buy the smallest thing that surprises you.",
        "Wait five extra minutes before leaving.",
        "Choose the slower path once today.",
        "Notice the exact moment the light changes.",
    ]
}

/// P3.0 #301 payload — everything the card view and notification need.
public struct OmenCardData: Codable, Hashable, Sendable, Identifiable {
    /// Start-of-local-day at compose time. Doubles as the omen's key so
    /// two calls on the same day dedupe cleanly.
    public let date: Date
    public let line: String
    public let microTask: String
    public let anchorExperienceId: String?
    public let anchorTitle: String?

    public var id: Date { date }

    public init(
        date: Date,
        line: String,
        microTask: String,
        anchorExperienceId: String? = nil,
        anchorTitle: String? = nil
    ) {
        self.date = date
        self.line = line
        self.microTask = microTask
        self.anchorExperienceId = anchorExperienceId
        self.anchorTitle = anchorTitle
    }
}

/// SplitMix64 — deterministic RNG. `Omen`-prefixed to avoid clashing
/// with any other SplitMix64 that might land in the target later.
private struct OmenSplitMix64 {
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

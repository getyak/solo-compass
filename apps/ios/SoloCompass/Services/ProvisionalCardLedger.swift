import Foundation

/// ⑩ Card 可反悔性 — slice A: pure state machine that gates every inline
/// `ChatCard` behind a 3-second **undo window** before it counts as
/// committed.
///
/// Design principles:
/// - **The model doesn't own the timeline.** A tool result used to pin
///   the card immediately — the user had no lever if the answer felt
///   wrong. Now every append lands as `provisional` and the user (or an
///   `undoLast()` call) can pull it before the deadline.
/// - **Two-clock separation.** Real time (the 3-second wall clock) drives
///   *auto-commit* on the UI side; the ledger itself is a **pure
///   function of `(entries, now)`** — feed it a `Date` and it tells you
///   which cards are still provisional, which are committed, which have
///   been undone. That keeps this file unit-testable with a fake clock
///   and lets `VoiceAgentOrchestrator` inject its own Timer to drive
///   real-time transitions.
/// - **Undo is reversible for the ledger's whole lifetime — commit is
///   irreversible.** Once a card is committed, `undo` is a no-op (the UI
///   should not offer it). This matches the mental model: "I can pull
///   the card back until it settles."
///
/// Slice B (UI wiring) reads this ledger via a derived `cards(now:)`
/// projection and shows a countdown pill on any entry whose
/// `state == .provisional`.
@MainActor
final class ProvisionalCardLedger {

    // MARK: - Value types

    /// The lifecycle of one card entry. The transitions are:
    ///
    ///   appended → provisional
    ///   provisional --(undo before deadline)-→ undone
    ///   provisional --(commit / deadline passes)-→ committed
    ///
    /// Once `undone` or `committed`, an entry never moves again.
    enum State: Equatable, Sendable {
        case provisional(deadline: Date)
        case committed
        case undone
    }

    struct Entry: Identifiable, Equatable {
        let id: UUID
        let messageId: UUID
        let card: ChatCard
        let appearedAt: Date
        private(set) var state: State

        init(
            id: UUID = UUID(),
            messageId: UUID,
            card: ChatCard,
            appearedAt: Date,
            state: State
        ) {
            self.id = id
            self.messageId = messageId
            self.card = card
            self.appearedAt = appearedAt
            self.state = state
        }

        fileprivate mutating func setState(_ new: State) { state = new }
    }

    // MARK: - Configuration

    /// How long a card stays revocable. 3 seconds is the observed
    /// user-comfort window from the ⑩ design brief: long enough to
    /// read the top line, short enough that the thread doesn't feel
    /// tentative.
    let undoWindow: TimeInterval

    // MARK: - Storage

    private(set) var entries: [Entry] = []

    // MARK: - Init

    init(undoWindow: TimeInterval = 3.0) {
        self.undoWindow = undoWindow
    }

    // MARK: - Mutation

    /// Append a new card in the `provisional` state. Deadline is
    /// `appearedAt + undoWindow`. Returns the created entry id so the
    /// caller can address it in `undo(id:)`.
    @discardableResult
    func append(
        card: ChatCard,
        to messageId: UUID,
        at now: Date
    ) -> UUID {
        let entry = Entry(
            messageId: messageId,
            card: card,
            appearedAt: now,
            state: .provisional(deadline: now.addingTimeInterval(undoWindow))
        )
        entries.append(entry)
        return entry.id
    }

    /// Pull the last still-provisional card back. Idempotent; returns
    /// `true` iff something was actually undone. Does not touch
    /// entries that are already `committed`.
    ///
    /// Uses reverse order so "last" means "most recently appended".
    @discardableResult
    func undoLast(at now: Date) -> Bool {
        promoteDueEntries(now: now)
        for i in entries.indices.reversed() {
            if case .provisional = entries[i].state {
                entries[i].setState(.undone)
                return true
            }
        }
        return false
    }

    /// Undo a specific entry by id — used when the user swipes / taps
    /// its own pill instead of the global "undo last". Idempotent.
    @discardableResult
    func undo(id: UUID, at now: Date) -> Bool {
        promoteDueEntries(now: now)
        guard let i = entries.firstIndex(where: { $0.id == id }) else {
            return false
        }
        if case .provisional = entries[i].state {
            entries[i].setState(.undone)
            return true
        }
        return false
    }

    /// Force every provisional entry to `committed` right now. Used
    /// when the next user turn starts (any card the user didn't undo
    /// during their read pass is theirs) or on session teardown.
    func commitAllProvisional() {
        for i in entries.indices {
            if case .provisional = entries[i].state {
                entries[i].setState(.committed)
            }
        }
    }

    /// Advance the clock and settle every provisional entry whose
    /// deadline has passed. Drives auto-commit; called both from the
    /// public projection helpers and from any real-time timer tick.
    func promoteDueEntries(now: Date) {
        for i in entries.indices {
            if case .provisional(let deadline) = entries[i].state, now >= deadline {
                entries[i].setState(.committed)
            }
        }
    }

    /// Drop every entry. Used when the session resets.
    func removeAll() {
        entries.removeAll(keepingCapacity: true)
    }

    // MARK: - Projections

    /// Every entry that is currently visible in the UI at `now`, in
    /// insertion order. Undone entries are excluded; still-provisional
    /// and committed entries are both included (the UI distinguishes
    /// them via `state`).
    func visibleEntries(at now: Date) -> [Entry] {
        var snapshot = entries
        for i in snapshot.indices {
            if case .provisional(let deadline) = snapshot[i].state, now >= deadline {
                snapshot[i].setState(.committed)
            }
        }
        return snapshot.filter {
            if case .undone = $0.state { return false }
            return true
        }
    }

    /// Convenience view for the existing `cardsByMessageId: [UUID: [ChatCard]]`
    /// contract on `VoiceAgentOrchestrator`. Preserves insertion order
    /// per message id so the chat rail renders exactly as before.
    func cardsByMessageId(at now: Date) -> [UUID: [ChatCard]] {
        var out: [UUID: [ChatCard]] = [:]
        for e in visibleEntries(at: now) {
            out[e.messageId, default: []].append(e.card)
        }
        return out
    }

    /// The next moment at which *something* transitions (soonest
    /// deadline among the still-provisional entries). `nil` when
    /// nothing is provisional. The orchestrator uses this to schedule
    /// a single-shot Timer instead of polling.
    func nextDeadline() -> Date? {
        entries.compactMap { e -> Date? in
            if case .provisional(let d) = e.state { return d }
            return nil
        }.min()
    }
}

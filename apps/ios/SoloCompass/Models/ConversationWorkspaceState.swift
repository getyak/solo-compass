import CoreGraphics
import Foundation
import Observation

/// Owns the single, continuous map / conversation scene.
///
/// Before this type the root map and the chat each kept private state and the
/// chat only existed while a modal sheet was on screen. Collapsing to the map,
/// opening discovery, or backgrounding the app could therefore discard the
/// draft, the section, or the agent itself. The workspace centralises exactly
/// the state that must survive a surface switch:
///
///   * which surface is showing (map / Ask Solo / discover) and how tall the
///     conversation panel is,
///   * the draft text (and staged attachments) the user is writing,
///   * scroll intent — whether new replies may follow, whether the
///     return-to-latest affordance should show,
///   * explicit ask requests (a seeded prompt from diagnostics, the FilterBar
///     "Ask Solo" pill, a place-scoped ask) delivered through one token so a
///     request raised while the panel was collapsed still reaches a chat that
///     is already mounted,
///   * a hibernation signal so opening a modal or backgrounding can stop the
///     mic/speech without ending the conversation.
///
/// It deliberately does **not** own the conversation itself — that stays on
/// `VoiceAgentOrchestrator` — nor the map selection, which stays on
/// `MapViewModel`, nor the live drag translation, which lives in the panel's
/// `@GestureState` so a cancelled gesture can never leave it stranded.
@MainActor
@Observable
public final class ConversationWorkspaceState {

    // MARK: - Surface

    /// The three top-level destinations of the workspace dock.
    public enum Surface: String, CaseIterable, Identifiable, Sendable {
        case map
        case ask
        case discover

        public var id: String { rawValue }
    }

    /// Height states of the conversation panel. Heights are derived from the
    /// live container height so the ratios stay honest across devices, Dynamic
    /// Type, and orientation instead of being pinned to pixels.
    public enum PanelDetent: String, CaseIterable, Identifiable, Sendable {
        case collapsed
        case conversation
        case expanded

        public var id: String { rawValue }

        /// Order used for one-step snapping.
        public static let ordered: [PanelDetent] = [.collapsed, .conversation, .expanded]

        /// The next larger detent, saturating at `.expanded`.
        public var larger: PanelDetent {
            switch self {
            case .collapsed: return .conversation
            case .conversation, .expanded: return .expanded
            }
        }

        /// The next smaller detent, saturating at `.collapsed`.
        public var smaller: PanelDetent {
            switch self {
            case .expanded: return .conversation
            case .conversation, .collapsed: return .collapsed
            }
        }
    }

    /// The keyboard's restore point: which detent to return to and the manual
    /// revision at the moment focus arrived. Restoration is skipped when the
    /// user pins a detent after focus (revision changed).
    public struct KeyboardSnapshot: Equatable, Sendable {
        public let detent: PanelDetent
        public let revision: Int
    }

    /// Shared geometry + gesture constants. Exposed (not private) so the panel
    /// and the focused tests describe the same numbers.
    public enum Metrics {
        /// Slim bar that keeps the handle + dock reachable while the map fills
        /// the rest of the screen. Tall enough to hold the 44pt grabber and the
        /// dock at the largest Dynamic Type without clipping.
        public static let collapsedHeight: CGFloat = 136
        /// Default entry: roughly four fifths conversation, leaving a clean map
        /// glimpse (city pill + avatar) on top. 0.78 of the safe height is
        /// ≥ 2/3 of the physical screen on modern devices.
        public static let conversationFraction: CGFloat = 0.78
        /// Near-full conversation for reading a long reply or composing.
        public static let expandedFraction: CGFloat = 0.95
        /// Vertical room reserved at the top of the container for the map
        /// chrome (city pill + filter bar). The conversation detent never grows
        /// past this, so the top map/city/avatar stay visible and safe even on
        /// short screens.
        public static let minTopClearance: CGFloat = 132
        /// Past an edge the drag is damped to this fraction of the excess so the
        /// panel resists being pulled off-screen instead of flying with the
        /// finger.
        public static let rubberBandDamping: CGFloat = 0.32
        /// Distance (points) at which the rubber band is roughly half-strength.
        public static let rubberBandScale: CGFloat = 140
    }

    // MARK: - Stored state

    public private(set) var surface: Surface = .ask
    public private(set) var detent: PanelDetent = .conversation

    /// Increments on every deliberate surface/detent choice. The keyboard
    /// restore path compares it so a manual choice made while typing wins.
    public private(set) var manualDetentRevision: Int = 0

    /// The user's in-progress composer text. Owned here so collapsing the panel
    /// or visiting the map never drops a half-written question.
    public var draftText: String = ""

    /// Staged, not-yet-sent attachments. Same reasoning as `draftText`.
    public var attachments: [LocalAttachment] = []

    /// A prompt that must be delivered to the agent even if the chat view was
    /// already mounted when it was raised (diagnostics seed, FilterBar pill,
    /// place-scoped ask). `promptToken` changes on every request so an
    /// `onChange` observer fires exactly once per request.
    public private(set) var pendingPrompt: String?
    public private(set) var promptToken: Int = 0
    /// Whether the request should also arm push-to-talk.
    public private(set) var pendingStartInVoice: Bool = false

    /// A dedicated voice-start request channel. Unlike `pendingPrompt`, this
    /// carries no text: the dock's long-press asks the already-mounted chat to
    /// open the voice surface and arm the mic, which `startInVoiceMode` cannot
    /// do once the view exists. `voiceStartPending` is consumable so a request
    /// raised before the chat mounted is not lost and is never delivered twice.
    public private(set) var voiceStartToken: Int = 0
    public private(set) var voiceStartPending: Bool = false

    /// A hibernate request channel. Raised when a modal is presented (history,
    /// settings, detail, routes, profile) so the chat stops the mic and speech
    /// while it is covered — without ending the conversation.
    public private(set) var hibernationToken: Int = 0

    /// True while the bottom of the message list is on screen. New replies only
    /// auto-follow when this is true (or the user explicitly sent / jumped).
    public private(set) var isNearBottom: Bool = true
    /// The chat's own follow intent for the current streaming turn. Set when the
    /// user sends or taps return-to-latest; cleared the moment they scroll away.
    public private(set) var followStreaming: Bool = false
    /// True when a reply arrived while the user was reading history — drives the
    /// return-to-latest pill.
    public private(set) var showsReturnToLatest: Bool = false

    /// The message id the reader had at the top of the viewport, so leaving the
    /// chat surface (map/discovery) and returning reopens the same row instead
    /// of the top of the transcript. Scoped to `anchorConversationId` and reset
    /// only on an intentional new/history conversation change or a send.
    public private(set) var visibleAnchorId: UUID?
    public private(set) var anchorConversationId: String?

    public init() {}

    // MARK: - Derived

    /// True when the panel is showing a compact conversation doorway rather than
    /// a full message list. Drives the reduced empty state.
    public var isCompactConversation: Bool {
        surface == .ask && detent == .conversation
    }

    /// True when the chat surface should be interactive at all.
    public var showsConversation: Bool {
        surface == .ask && detent != .collapsed
    }

    /// True when the discovery surface should be interactive.
    public var showsDiscovery: Bool {
        surface == .discover && detent != .collapsed
    }

    /// Whether the current frame should auto-follow new chat content. The reader
    /// being at the bottom is the single source of truth; `followStreaming` only
    /// carries an explicit send/jump until the reader scrolls away.
    public var shouldFollowScroll: Bool {
        isNearBottom || followStreaming
    }

    /// Target panel height (points) for the committed detent.
    public func targetPanelHeight(containerHeight: CGFloat) -> CGFloat {
        Self.panelHeight(
            for: detent,
            containerHeight: containerHeight,
            surface: surface
        )
    }

    /// Pure detent → height mapping. `.map` always collapses; discovery uses
    /// the expanded height so a route/nearby list has room. The conversation
    /// detent is capped so the top map/city/avatar chrome stays visible.
    public static func panelHeight(
        for detent: PanelDetent,
        containerHeight: CGFloat,
        surface: Surface = .ask
    ) -> CGFloat {
        let height = max(containerHeight, 1)
        switch detent {
        case .collapsed:
            return min(Metrics.collapsedHeight, height)
        case .conversation:
            let desired = height * Metrics.conversationFraction
            let ceiling = max(Metrics.collapsedHeight + 24, height - Metrics.minTopClearance)
            return min(height, max(Metrics.collapsedHeight + 24, min(desired, ceiling)))
        case .expanded:
            return min(height, max(Metrics.collapsedHeight + 24, height * Metrics.expandedFraction))
        }
    }

    // MARK: - Surface / detent transitions

    /// Select a dock surface, keeping the panel detent synchronized:
    /// `.map` collapses; `.ask` restores the conversation detent; `.discover`
    /// opens tall enough to browse. Selecting the already-active surface is a
    /// no-op and does not bump the revision.
    @discardableResult
    public func selectSurface(_ newSurface: Surface) -> Bool {
        guard newSurface != surface else { return false }
        switch newSurface {
        case .map:
            surface = .map
            detent = .collapsed
        case .ask:
            if surface == .map || surface == .discover || detent == .collapsed {
                detent = .conversation
            }
            surface = .ask
        case .discover:
            surface = .discover
            detent = .expanded
        }
        manualDetentRevision &+= 1
        return true
    }

    /// Commit a panel detent, keeping the surface tab in sync: collapsing to the
    /// map selects the map tab; any taller detent returns to the chat tab (or
    /// keeps discovery if it was selected). A no-op returns false.
    @discardableResult
    public func selectDetent(_ newDetent: PanelDetent) -> Bool {
        guard newDetent != detent else { return false }
        detent = newDetent
        if newDetent == .collapsed {
            surface = .map
        } else if surface == .map {
            surface = .ask
        }
        manualDetentRevision &+= 1
        return true
    }

    /// Expand once for keyboard focus. Focus is not a manual pin, so this must
    /// not bump the manual revision. Returns the restore snapshot (which detent
    /// and the revision at that moment).
    public func expandForKeyboard() -> KeyboardSnapshot {
        let snapshot = KeyboardSnapshot(detent: detent, revision: manualDetentRevision)
        if surface == .map {
            surface = .ask
        }
        if detent != .expanded {
            detent = .expanded
        }
        return snapshot
    }

    /// Restore the detent captured by `expandForKeyboard` when the keyboard
    /// dismisses — but only when the user has not made a manual detent/surface
    /// choice since focus arrived.
    public func restoreAfterKeyboard(_ snapshot: KeyboardSnapshot) {
        guard manualDetentRevision == snapshot.revision else { return }
        detent = snapshot.detent
        if snapshot.detent == .collapsed {
            surface = .map
        }
    }

    /// The agent started / stopped working. Auto-expand only when the user is
    /// already in the chat and hasn't pinned a detent — never yank them back
    /// from the map or from a deliberately chosen half height.
    public func autoExpandWhileWorking() {
        guard surface == .ask, detent == .conversation else { return }
        detent = .expanded
    }

    // MARK: - Drag geometry (pure)

    /// Rubber-band a dragged height within `[collapsedHeight, containerHeight]`.
    public static func clampDraggedHeight(
        _ proposed: CGFloat,
        containerHeight: CGFloat
    ) -> CGFloat {
        let upper = max(containerHeight * Metrics.expandedFraction, Metrics.collapsedHeight)
        let lower = Metrics.collapsedHeight
        if proposed > upper {
            return upper + rubberBand(proposed - upper)
        }
        if proposed < lower {
            return lower - rubberBand(lower - proposed)
        }
        return proposed
    }

    /// Damped overshoot: linear near the edge, asymptotic far from it.
    public static func rubberBand(_ excess: CGFloat) -> CGFloat {
        guard excess > 0 else { return excess }
        return excess * Metrics.rubberBandDamping
            * (Metrics.rubberBandScale / (Metrics.rubberBandScale + excess))
    }

    /// Decide which detent a release commits to.
    ///
    /// `proposedHeight` is where the finger let go; `projectedHeight` is where
    /// the gesture was heading (`predictedEndTranslation`, a displacement — not
    /// a velocity). We snap to the detent nearest the *projection*, then clamp
    /// the move to a single step from `current`, so one flick can never skip the
    /// detent the user was aiming at.
    public static func snapDetent(
        current: PanelDetent,
        proposedHeight: CGFloat,
        projectedHeight: CGFloat,
        containerHeight: CGFloat
    ) -> PanelDetent {
        let ordered = PanelDetent.ordered
        let heights = ordered.map { panelHeight(for: $0, containerHeight: containerHeight) }
        let projectedIndex = nearestIndex(to: projectedHeight, in: heights)
        guard let currentIndex = ordered.firstIndex(of: current) else {
            return ordered[projectedIndex]
        }
        // A release with essentially no projection stays put.
        if abs(projectedHeight - heights[currentIndex]) < 1 {
            return current
        }
        let clamped = min(max(projectedIndex, currentIndex - 1), currentIndex + 1)
        return ordered[clamped]
    }

    private static func nearestIndex(to value: CGFloat, in values: [CGFloat]) -> Int {
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, candidate) in values.enumerated() {
            let distance = abs(candidate - value)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    // MARK: - Explicit ask channel

    /// Raise an explicit ask. The token increments even when the text is
    /// identical to the previous one, so requesting the same seeded prompt
    /// twice still reaches the agent without a duplicate on a single request.
    public func requestPrompt(_ text: String, startInVoice: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingPrompt = trimmed
        pendingStartInVoice = startInVoice
        promptToken &+= 1
        // An explicit ask is a deliberate return to the conversation.
        if surface != .ask {
            surface = .ask
            detent = .conversation
            manualDetentRevision &+= 1
        }
    }

    /// Consume the pending ask exactly once. Returns nil when there is nothing
    /// waiting (or it was already consumed).
    public func consumePendingPrompt() -> (text: String, startInVoice: Bool)? {
        guard let text = pendingPrompt else { return nil }
        pendingPrompt = nil
        let voice = pendingStartInVoice
        pendingStartInVoice = false
        return (text, voice)
    }

    /// Drop a pending ask without delivering it.
    public func discardPendingPrompt() {
        pendingPrompt = nil
        pendingStartInVoice = false
    }

    /// Ask the mounted chat to open the voice surface and arm push-to-talk.
    public func requestVoiceStart() {
        voiceStartPending = true
        voiceStartToken &+= 1
        if surface != .ask {
            surface = .ask
            manualDetentRevision &+= 1
        }
        if detent == .collapsed {
            detent = .conversation
            manualDetentRevision &+= 1
        }
    }

    /// Consume a pending voice-start request exactly once.
    public func consumeVoiceStart() -> Bool {
        guard voiceStartPending else { return false }
        voiceStartPending = false
        return true
    }

    /// Ask the mounted chat to stop the mic and speech without ending the
    /// conversation — raised when a modal covers the chat or the app backgrounds.
    public func requestHibernation() {
        hibernationToken &+= 1
    }

    /// True while the software keyboard is on screen. The panel uses this honest
    /// frame signal to drop the dock while composing, so the composer sits just
    /// above the keyboard instead of leaving the dock wedged between them.
    public private(set) var isSoftwareKeyboardVisible: Bool = false

    public func setSoftwareKeyboardVisible(_ visible: Bool) {
        guard isSoftwareKeyboardVisible != visible else { return }
        isSoftwareKeyboardVisible = visible
    }

    // MARK: - Scroll intent

    public func noteReachedBottom() {
        isNearBottom = true
        showsReturnToLatest = false
    }

    /// The reader scrolled up. Clears the follow intent so a rapid token stream
    /// can never keep yanking them down after the first send.
    public func noteScrolledAwayFromBottom() {
        isNearBottom = false
        followStreaming = false
    }

    /// The user sent a message or tapped return-to-latest: follow this turn and
    /// drop the reading anchor.
    public func beginFollowing() {
        followStreaming = true
        isNearBottom = true
        showsReturnToLatest = false
        visibleAnchorId = nil
    }

    // MARK: - Reading anchor

    /// Bind the anchor to a conversation. A different conversation id (a new
    /// chat, or a restored history record) clears the anchor so the transcript
    /// opens at its intended position rather than a stale row.
    public func syncAnchorConversation(id: String) {
        guard anchorConversationId != id else { return }
        anchorConversationId = id
        visibleAnchorId = nil
    }

    public func noteVisibleAnchor(_ id: UUID?) {
        visibleAnchorId = id
    }

    public func clearVisibleAnchor() {
        visibleAnchorId = nil
    }

    /// A new reply landed while the user was reading history.
    public func noteContentArrivedWhileAway() {
        guard !isNearBottom else { return }
        showsReturnToLatest = true
        followStreaming = false
    }

    public func endFollowing() {
        followStreaming = false
    }
}

/// Stable accessibility identifiers for the conversation workspace. Views and
/// UI tests both read these, so the parent can replay the surface by identifier
/// in a real simulator without depending on localized copy.
public enum WorkspaceAccessibility {
    public static let overlay = "workspace.overlay"
    public static let panel = "workspace.panel"
    public static let handle = "workspace.handle"
    public static let dock = "workspace.dock"
    public static let chat = "workspace.chat"
    public static let collapseChat = "workspace.chat.collapse"
    public static let composer = "workspace.composer"
    public static let returnToLatest = "workspace.returnToLatest"
    public static let discover = "workspace.discover"

    public static func dockItem(_ surface: ConversationWorkspaceState.Surface) -> String {
        "workspace.dock.\(surface.rawValue)"
    }
}

/// A bounded throttle for streaming scroll-follow requests.
///
/// Streaming tokens arrive many times a second. A *debounce* (cancel + restart
/// on every token) can starve the follow until generation ends; this schedules
/// at most one trailing action per window instead. The action is re-evaluated
/// at execution time against the reader's current intent, so a token that lands
/// while the reader is scrolling up will not drag them back to the bottom.
@MainActor
public final class ScrollFollowThrottle {
    private var pending: Task<Void, Never>?
    /// Number of actions actually executed. Test-visible.
    public private(set) var fireCount: Int = 0
    /// Number of scheduled windows started. Test-visible.
    public private(set) var scheduleCount: Int = 0

    public init() {}

    /// Request a follow. `interval` is the minimum spacing between actions. The
    /// `shouldFollow` closure is evaluated at execution time (not at request
    /// time) so the latest intent wins.
    public func request(
        interval: Duration = .milliseconds(120),
        shouldFollow: @escaping @MainActor () -> Bool,
        action: @escaping @MainActor () -> Void
    ) {
        guard pending == nil else { return }
        scheduleCount &+= 1
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: interval)
            guard let self, !Task.isCancelled else { return }
            self.pending = nil
            guard shouldFollow() else { return }
            self.fireCount &+= 1
            action()
        }
    }

    /// Cancel any pending action (panel hidden, app backgrounded, teardown).
    public func cancel() {
        pending?.cancel()
        pending = nil
    }

    /// True while an action is scheduled. Test-visible.
    public var isPending: Bool { pending != nil }
}

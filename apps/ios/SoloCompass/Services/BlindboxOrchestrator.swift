import Foundation
import Observation
import os

/// P2.3 #231 + #233: state machine for a blindbox trip.
///
/// Flow (per PRD §5.2):
/// 1. `launch(durationHours:)` picks 2–5 anchor experiences based on
///    `mapViewModel.visibleExperiences` filtered by taste and un-visited
///    status. On the FIRST launch for a fresh user (`SafetyPolicy.firstRun`)
///    we bias hard toward high-`confidence` + high `soloScore` picks so
///    the surprise doesn't backfire (#233).
/// 2. State transitions: `.idle → .inProgress → .approaching → .arrived →
///    .revealed → .idle` per anchor. Callers observe `state` +
///    `currentAnchor` to drive the UI.
/// 3. `reshuffle()` is free (no `SubscriptionService` decrement); the
///    entry itself is paywalled by the launch UI (#230).
/// 4. LiveActivity: hands off to `LiveActivityService.startSoloAgentHint`
///    with a masked anchor name so the island doesn't spoil the reveal.
///
/// Persistence: the trip lives only in memory. If the app dies mid-trip
/// the user picks a new blindbox — deliberate, because a resumed trip
/// with stale weather / traffic would be worse than a fresh one.
@MainActor
@Observable
public final class BlindboxOrchestrator {

    public enum Stage: Equatable {
        case idle
        case inProgress(anchorIndex: Int)
        case approaching(anchorIndex: Int)
        case arrived(anchorIndex: Int)
        case revealed(anchorIndex: Int)
        case finished
    }

    public enum SafetyPolicy {
        /// A brand-new user gets only high-confidence + high-solo-score picks.
        case firstRun
        /// Returning users get the full curated pool.
        case normal
    }

    public private(set) var stage: Stage = .idle
    public private(set) var anchors: [Experience] = []
    public private(set) var safetyPolicy: SafetyPolicy = .firstRun
    public private(set) var reshufflesUsed: Int = 0

    private weak var mapViewModel: MapViewModel?
    private let preferences: UserPreferences
    private let log = OSLog(subsystem: "com.solocompass.app", category: "Blindbox")

    public init(mapViewModel: MapViewModel?, preferences: UserPreferences) {
        self.mapViewModel = mapViewModel
        self.preferences = preferences
    }

    /// Compose a fresh set of anchors. Duration bucket controls the anchor
    /// count: 1h → 2 anchors, 3h → 3, all-day → 5. Returns whether the
    /// pool had enough candidates to launch.
    @discardableResult
    public func launch(durationHours: Double) -> Bool {
        guard let vm = mapViewModel else { return false }
        safetyPolicy = preferences.completedExperiences.isEmpty ? .firstRun : .normal

        let targetCount: Int
        switch durationHours {
        case ..<2.0: targetCount = 2
        case 2.0..<6.0: targetCount = 3
        default: targetCount = 5
        }

        let pool = candidatePool(from: vm.visibleExperiences)
        guard pool.count >= 2 else {
            os_log("Blindbox: candidate pool too thin (%d)", log: log, type: .info, pool.count)
            return false
        }
        anchors = Array(pool.prefix(targetCount))
        stage = .inProgress(anchorIndex: 0)
        reshufflesUsed = 0
        return true
    }

    /// Filter + rank the visible pool per the current safety policy.
    /// Extracted so tests can exercise the ranking without spinning a
    /// full MapViewModel.
    public func candidatePool(from visible: [Experience]) -> [Experience] {
        let unvisited = visible.filter { !preferences.completedExperiences.contains($0.id) }
        switch safetyPolicy {
        case .firstRun:
            // firstRun bias: only high-solo-score picks AND a confidence
            // level of 3+ (Confidence.level is Int 0–5).
            let solo = unvisited.filter { $0.soloScore.overall >= 7.0 }
            let confident = solo.filter { $0.confidence.level >= 3 }
            return confident.sorted { $0.soloScore.overall > $1.soloScore.overall }
        case .normal:
            return unvisited
                .sorted { $0.soloScore.overall > $1.soloScore.overall }
        }
    }

    /// User walks up to the current anchor.
    public func markApproaching() {
        guard case .inProgress(let idx) = stage else { return }
        stage = .approaching(anchorIndex: idx)
    }

    /// User is within the ±100m arrival ring — reveal the anchor next.
    public func markArrived() {
        guard case .approaching(let idx) = stage else { return }
        stage = .arrived(anchorIndex: idx)
    }

    /// Reveal the current anchor (name + description now visible).
    public func revealCurrent() {
        guard case .arrived(let idx) = stage else { return }
        stage = .revealed(anchorIndex: idx)
    }

    /// Move to the next anchor, or terminate if we've finished.
    public func advance() {
        guard case .revealed(let idx) = stage else { return }
        let next = idx + 1
        if next >= anchors.count {
            stage = .finished
        } else {
            stage = .inProgress(anchorIndex: next)
        }
    }

    /// Rebuild the anchor pool. Free of charge — the entry paywall (#230)
    /// already gated cost.
    @discardableResult
    public func reshuffle() -> Bool {
        reshufflesUsed += 1
        return launch(durationHours: Double(anchors.count))
    }

    /// Convenience for tests / SwiftUI overlays that want the current
    /// anchor without unwrapping the enum every time.
    public var currentAnchor: Experience? {
        switch stage {
        case .inProgress(let i), .approaching(let i), .arrived(let i), .revealed(let i):
            return blindboxSafeAnchor(at: i)
        default:
            return nil
        }
    }

    private func blindboxSafeAnchor(at index: Int) -> Experience? {
        (0..<anchors.count).contains(index) ? anchors[index] : nil
    }
}

import Foundation
import ActivityKit
import Observation
import os

/// Starts, updates, and ends the four SoloCompass Live Activities (US-026):
/// route / countdown / recording / compile. All activities are **local** —
/// `Activity.request` + `activity.update` drive the Dynamic Island without any
/// APNs push token, so this stays clear of the disabled push provisioning.
///
/// One activity runs at a time (the app never overlaps these scenarios). The
/// service keeps a single `Activity<SoloCompassActivityAttributes>` handle plus
/// its `kind`, so callers can start one and end it without juggling references.
///
/// Each `start*` reads from real app models (Route / RouteCompanion /
/// VoiceService / AIService) and maps them onto `SoloCompassActivityState`. The
/// widget extension renders that state — see `SoloCompassLiveActivity`.
@MainActor
@Observable
public final class LiveActivityService {
    public static let shared = LiveActivityService()

    private static let log = OSLog(subsystem: "com.solocompass.app", category: "LiveActivity")

    /// The currently running activity, if any. Read-only to callers.
    public private(set) var current: Activity<SoloCompassActivityAttributes>?
    /// Which scenario `current` represents (mirrors `current.attributes.kind`).
    public private(set) var currentKind: SoloCompassActivityAttributes.Kind?

    private init() {}

    /// Whether the user has Live Activities enabled for the app. Surfaces in UI
    /// so a "show in Dynamic Island" affordance can hide when off.
    public var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Route — 路线进行中

    /// Begin a route Live Activity. `nextStopName` should be a short place name
    /// (Experience.placeNameRomanized ?? placeNameLocal ?? title) — never the
    /// long `title` sentence — so the island reads cleanly.
    @discardableResult
    public func startRoute(
        routeTitle: String,
        nextStopName: String,
        nextStopMeta: String,
        etaText: String,
        currentStopIndex: Int,
        totalStops: Int
    ) -> Bool {
        let state = SoloCompassActivityState(
            routeTitle: routeTitle,
            nextStopName: nextStopName,
            nextStopMeta: nextStopMeta,
            etaText: etaText,
            currentStopIndex: currentStopIndex,
            totalStops: totalStops
        )
        return start(kind: .route, state: state)
    }

    /// Advance the route activity to a new stop / ETA.
    public func updateRoute(
        nextStopName: String,
        nextStopMeta: String,
        etaText: String,
        currentStopIndex: Int,
        totalStops: Int
    ) async {
        guard currentKind == .route, var state = current?.content.state else { return }
        state.nextStopName = nextStopName
        state.nextStopMeta = nextStopMeta
        state.etaText = etaText
        state.currentStopIndex = currentStopIndex
        state.totalStops = totalStops
        await update(state)
    }

    // MARK: - Countdown — 出发倒计时

    /// Begin a companion-group departure countdown. The widget renders a live
    /// timer against `departureDate`, so the OS ticks the seconds for us.
    @discardableResult
    public func startCountdown(
        groupTitle: String,
        meetPointName: String,
        departureDate: Date,
        memberInitials: [String],
        memberSummary: String
    ) -> Bool {
        let state = SoloCompassActivityState(
            departureDate: departureDate,
            meetPointName: meetPointName,
            groupTitle: groupTitle,
            memberInitials: memberInitials,
            memberSummary: memberSummary
        )
        return start(kind: .countdown, state: state)
    }

    // MARK: - Recording — 录制语音 signal

    /// Begin a voice-recording activity. Call `updateRecording(amplitude:)` from
    /// the capture loop (e.g. observing `VoiceService.amplitude`) to feed the
    /// waveform; the duration ticks itself from `startDate`.
    @discardableResult
    public func startRecording(
        startDate: Date = Date(),
        locality: String
    ) -> Bool {
        let state = SoloCompassActivityState(
            recordingStartDate: startDate,
            waveformSamples: [],
            recordingLocality: locality
        )
        return start(kind: .recording, state: state)
    }

    /// Push a new amplitude sample into the rolling waveform window. Keeps the
    /// last `window` samples so the bars scroll without growing the ContentState.
    public func updateRecording(amplitude: Double, window: Int = 26) async {
        guard currentKind == .recording, var state = current?.content.state else { return }
        var samples = state.waveformSamples
        samples.append(min(max(amplitude, 0), 1))
        if samples.count > window { samples.removeFirst(samples.count - window) }
        state.waveformSamples = samples
        await update(state)
    }

    /// Background sampler that polls a live amplitude source a few times a
    /// second and feeds the waveform. `VoiceService.amplitude` updates at ~60fps,
    /// but ActivityKit throttles (and drains battery) if you push every frame —
    /// so we sample at a calm cadence instead of mirroring every tick.
    private var recordingSampler: Task<Void, Never>?

    /// Begin a recording activity AND start sampling its waveform from
    /// `amplitudeProvider` (e.g. `{ voiceService.amplitude }`). Both ChatSheet
    /// and VoiceButton call this single entry so the island/lifecycle logic
    /// lives in one place. The sampler stops when `endRecordingSession()` (or any
    /// other activity start, or `end()`) runs.
    public func beginRecordingSession(
        locality: String,
        amplitudeProvider: @escaping @MainActor () -> Double
    ) {
        guard startRecording(locality: locality) else { return }
        recordingSampler?.cancel()
        recordingSampler = Task { @MainActor [weak self] in
            // ~3 samples/sec keeps the bars lively while staying well under
            // ActivityKit's update budget.
            while !Task.isCancelled, self?.currentKind == .recording {
                await self?.updateRecording(amplitude: amplitudeProvider())
                try? await Task.sleep(nanoseconds: 330_000_000)
            }
        }
    }

    /// End the recording activity and stop the waveform sampler.
    public func endRecordingSession() async {
        recordingSampler?.cancel()
        recordingSampler = nil
        if currentKind == .recording { await end() }
    }

    // MARK: - Compile — AI 编排中

    /// Begin an AI-synthesis activity (evening page/route compile). Pass
    /// `progress` 0–1, or -1 for an indeterminate shimmer.
    @discardableResult
    public func startCompile(
        title: String,
        subtitle: String,
        progress: Double = -1
    ) -> Bool {
        let state = SoloCompassActivityState(
            compileTitle: title,
            compileSubtitle: subtitle,
            compileProgress: progress
        )
        return start(kind: .compile, state: state)
    }

    /// Update compile progress (0–1).
    public func updateCompile(progress: Double) async {
        guard currentKind == .compile, var state = current?.content.state else { return }
        state.compileProgress = progress
        await update(state)
    }

    // MARK: - End

    /// End the running activity immediately and drop the handle.
    public func end() async {
        guard let activity = current else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        current = nil
        currentKind = nil
    }

    // MARK: - Core start / update

    /// Request a new activity, ending any prior one first (one-at-a-time). Returns
    /// false when Live Activities are disabled or the request throws.
    @discardableResult
    private func start(
        kind: SoloCompassActivityAttributes.Kind,
        state: SoloCompassActivityState
    ) -> Bool {
        guard isEnabled else {
            os_log("LiveActivity start(%{public}@) skipped — activities disabled by user/system",
                   log: Self.log, type: .info, kind.rawValue)
            return false
        }

        // Tear down any prior activity so we never stack two — fire-and-forget
        // the async end, then request the new one.
        if let prior = current {
            current = nil
            currentKind = nil
            Task { await prior.end(nil, dismissalPolicy: .immediate) }
        }

        do {
            let activity = try Activity.request(
                attributes: SoloCompassActivityAttributes(kind: kind),
                content: .init(state: state, staleDate: nil),
                pushType: nil   // local-only; no APNs
            )
            current = activity
            currentKind = kind
            os_log("LiveActivity start(%{public}@) ok — id=%{public}@",
                   log: Self.log, type: .info, kind.rawValue, activity.id)
            return true
        } catch {
            // Non-critical — the in-app UI is the primary surface; the island is
            // an enhancement. Log the reason instead of swallowing silently, so a
            // failed request (entitlement, budget, throttle) is diagnosable.
            os_log("LiveActivity start(%{public}@) failed: %{public}@",
                   log: Self.log, type: .error, kind.rawValue, String(describing: error))
            current = nil
            currentKind = nil
            return false
        }
    }

    private func update(_ state: SoloCompassActivityState) async {
        guard let activity = current else { return }
        await activity.update(.init(state: state, staleDate: nil))
    }
}

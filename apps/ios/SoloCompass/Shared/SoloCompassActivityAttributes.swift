import Foundation
import ActivityKit

/// Live Activity attributes shared between the main app (which starts and
/// updates activities) and the `SoloCompassWidgets` extension (which renders
/// them on the Lock Screen and in the Dynamic Island).
///
/// One attributes type carries all four scenarios via a `kind` discriminator on
/// the dynamic `ContentState`, instead of four separate Activity types. iOS only
/// surfaces one Live Activity in the compact Dynamic Island at a time, and the
/// app never runs two of these scenarios concurrently — so a single attributes
/// type keeps the widget's `ActivityConfiguration` to one declaration while the
/// `ContentState.kind` switch drives which layout renders.
///
/// Design source: `island_notif.jsx` / `island_notif.css` from the
/// claude.ai/design handoff (DayPage warm-amber system). Five island scenarios
/// were specced; four are wired to real app state here (route / countdown /
/// recording / compile). Navigation is omitted — the app has no turn-by-turn
/// engine yet, so a live nav activity would have nothing real to update.
///
/// This file is compiled into BOTH targets. Keep it dependency-free (Foundation
/// + ActivityKit only) so it never pulls SwiftUI or app services into the
/// extension.
public struct SoloCompassActivityAttributes: ActivityAttributes {
    public typealias ContentState = SoloCompassActivityState

    /// Which scenario this activity represents. Fixed for the lifetime of the
    /// activity — the `kind` never changes once started, so the widget can pick
    /// its layout from `attributes.kind` and read scenario-specific fields off
    /// `ContentState`.
    public let kind: Kind

    public enum Kind: String, Codable, Hashable, Sendable {
        case route       // 路线进行中 — following a route, next stop + walking ETA + progress
        case countdown   // 出发倒计时 — companion group nearing its meet time
        case recording   // 录制语音 signal — capturing a voice signal, live waveform + duration
        case compile     // AI 编排中 — synthesizing today's page from the day's signals
    }

    public init(kind: Kind) {
        self.kind = kind
    }
}

/// The mutable per-frame state pushed via `activity.update(...)`.
///
/// A single flat struct holds the union of all four scenarios' fields; only the
/// subset relevant to `attributes.kind` is populated. ActivityKit budgets the
/// serialized `ContentState` to ~4KB, which this stays comfortably under.
public struct SoloCompassActivityState: Codable, Hashable, Sendable {

    // MARK: route — 路线进行中

    /// Route title, e.g. "湄公河日落散步". Shown as the expanded header.
    public var routeTitle: String
    /// Short name of the next stop, e.g. "昭阿努翁雕像". Use Experience.shortName,
    /// never the long `title` sentence.
    public var nextStopName: String
    /// Free-form walking-distance meta, e.g. "步行 7 分 · 540 m · 河堤一带".
    public var nextStopMeta: String
    /// Wall-clock arrival estimate as a display string, e.g. "17:49".
    public var etaText: String
    /// 1-based index of the current stop and total stop count (e.g. 2 / 3).
    public var currentStopIndex: Int
    public var totalStops: Int

    // MARK: countdown — 出发倒计时

    /// The absolute instant the group sets off. The widget renders a live
    /// `Text(timerInterval:)` against this, so the OS ticks the countdown for
    /// us without the app pushing every second.
    public var departureDate: Date?
    /// Meet-point short name, e.g. "昭阿努翁雕像".
    public var meetPointName: String
    /// Group title, e.g. "同伴团 · 30 分钟后集合".
    public var groupTitle: String
    /// Up to ~3 member initials for the avatar stack (e.g. ["M", "你", "T"]).
    public var memberInitials: [String]
    /// Human roster line, e.g. "Maya(主理) · 你 · Tomas".
    public var memberSummary: String

    // MARK: recording — 录制语音 signal

    /// The instant recording began. Drives the live duration via
    /// `Text(timerInterval:)`.
    public var recordingStartDate: Date?
    /// Latest normalized amplitude 0–1 from `VoiceService.amplitude`, sampled
    /// for the waveform. A short rolling window keeps the bars lively without
    /// flooding `update(...)`.
    public var waveformSamples: [Double]
    /// Locality hint shown under the title, e.g. "万象 河堤".
    public var recordingLocality: String

    // MARK: compile — AI 编排中

    /// Headline for the synthesis, e.g. "正在编排今日页面".
    public var compileTitle: String
    /// Mono sub-line, e.g. "12 条 signal · 3 个地点".
    public var compileSubtitle: String
    /// 0–1 progress; drives the shimmer skeleton fill. -1 means indeterminate.
    public var compileProgress: Double

    public init(
        routeTitle: String = "",
        nextStopName: String = "",
        nextStopMeta: String = "",
        etaText: String = "",
        currentStopIndex: Int = 0,
        totalStops: Int = 0,
        departureDate: Date? = nil,
        meetPointName: String = "",
        groupTitle: String = "",
        memberInitials: [String] = [],
        memberSummary: String = "",
        recordingStartDate: Date? = nil,
        waveformSamples: [Double] = [],
        recordingLocality: String = "",
        compileTitle: String = "",
        compileSubtitle: String = "",
        compileProgress: Double = -1
    ) {
        self.routeTitle = routeTitle
        self.nextStopName = nextStopName
        self.nextStopMeta = nextStopMeta
        self.etaText = etaText
        self.currentStopIndex = currentStopIndex
        self.totalStops = totalStops
        self.departureDate = departureDate
        self.meetPointName = meetPointName
        self.groupTitle = groupTitle
        self.memberInitials = memberInitials
        self.memberSummary = memberSummary
        self.recordingStartDate = recordingStartDate
        self.waveformSamples = waveformSamples
        self.recordingLocality = recordingLocality
        self.compileTitle = compileTitle
        self.compileSubtitle = compileSubtitle
        self.compileProgress = compileProgress
    }
}

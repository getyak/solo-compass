import SwiftUI
import WidgetKit
import ActivityKit

/// The Live Activity widget — one `ActivityConfiguration` driving all four
/// scenarios (route / countdown / recording / compile) via `attributes.kind`.
///
/// Layout maps the design's three island states onto ActivityKit's regions:
///   · minimal      → `.minimal` (one glyph)
///   · compact      → `.compactLeading` + `.compactTrailing`
///   · expanded     → the `.expanded` regions (the long-press big card)
///   · lock screen  → the configuration's `content` closure (the banner card)
///
/// Visual language is a direct port of `island_notif.css`: black island glass,
/// cream text, JetBrains-Mono numbers (SF Mono stand-in), sun-gold accents, and
/// the warm-amber DayPage system throughout.
struct SoloCompassLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SoloCompassActivityAttributes.self) { context in
            // Lock Screen / banner presentation.
            LockScreenLiveActivityView(kind: context.attributes.kind, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.92))
                .activitySystemActionForegroundColor(IP.sunGoldSoft)
        } dynamicIsland: { context in
            let kind = context.attributes.kind
            let state = context.state
            return DynamicIsland {
                expandedRegions(kind: kind, state: state)
            } compactLeading: {
                CompactLeading(kind: kind, state: state)
            } compactTrailing: {
                CompactTrailing(kind: kind, state: state)
            } minimal: {
                MinimalGlyph(kind: kind, state: state)
            }
            .keylineTint(IP.sunGold)
        }
    }

    // MARK: - Expanded regions

    /// `DynamicIslandExpandedContentBuilder` is a restricted result builder with
    /// no `buildEither`, so it can't host a `switch` directly. Keep the four
    /// regions fixed and push the per-scenario branching down into ordinary
    /// `@ViewBuilder` views (`ExpandedLeading` / `…Trailing` / `…Center` /
    /// `…Bottom`), which each `switch` on `kind` freely.
    @DynamicIslandExpandedContentBuilder
    private func expandedRegions(
        kind: SoloCompassActivityAttributes.Kind,
        state: SoloCompassActivityState
    ) -> DynamicIslandExpandedContent<some View> {
        DynamicIslandExpandedRegion(.leading) {
            ExpandedLeading(kind: kind)
        }
        DynamicIslandExpandedRegion(.trailing) {
            ExpandedTrailing(kind: kind, state: state)
        }
        DynamicIslandExpandedRegion(.center) {
            ExpandedCenter(kind: kind, state: state)
        }
        DynamicIslandExpandedRegion(.bottom) {
            ExpandedBottom(kind: kind, state: state)
        }
    }
}

// MARK: - Expanded region dispatchers (per-scenario @ViewBuilder switches)

private struct ExpandedLeading: View {
    let kind: SoloCompassActivityAttributes.Kind
    var body: some View {
        switch kind {
        case .route:     IslandIconTile(systemName: "location.north.circle.fill")
        case .countdown: IslandIconTile(systemName: "person.2.fill")
        case .recording: IslandIconTile(systemName: "mic.fill", fill: IP.recTile, tint: IP.rec)
        case .compile:   IslandIconTile(systemName: "sparkles")
        }
    }
}

private struct ExpandedTrailing: View {
    let kind: SoloCompassActivityAttributes.Kind
    let state: SoloCompassActivityState
    var body: some View {
        switch kind {
        case .route:     IslandPill(text: "\(state.currentStopIndex) / \(state.totalStops) 站")
        case .countdown: CountdownPill(date: state.departureDate)
        case .recording: RecPill(start: state.recordingStartDate)
        case .compile:   IslandCompileDots()
        }
    }
}

private struct ExpandedCenter: View {
    let kind: SoloCompassActivityAttributes.Kind
    let state: SoloCompassActivityState
    var body: some View {
        switch kind {
        case .route:
            ExpandedTitle(title: state.routeTitle, sub: "进行中 · 第 \(state.currentStopIndex) 站")
        case .countdown:
            ExpandedTitle(title: state.groupTitle, sub: state.meetPointName, subIcon: "mappin.and.ellipse")
        case .recording:
            RecordingTitle(locality: state.recordingLocality)
        case .compile:
            ExpandedTitle(title: state.compileTitle, sub: state.compileSubtitle)
        }
    }
}

private struct ExpandedBottom: View {
    let kind: SoloCompassActivityAttributes.Kind
    let state: SoloCompassActivityState
    var body: some View {
        switch kind {
        case .route:
            RouteBottom(state: state)
        case .countdown:
            CountdownBottom(state: state)
        case .recording:
            IslandWaveform(samples: state.waveformSamples, barCount: 26, height: 34)
                .padding(.top, 4)
        case .compile:
            CompileSkeleton(progress: state.compileProgress)
                .padding(.top, 6)
        }
    }
}

// MARK: - Shared expanded header

/// Title + uppercase mono subtitle used by route / countdown / compile centers.
struct ExpandedTitle: View {
    let title: String
    let sub: String
    var subIcon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.islandDisplay(14, .semibold))
                .foregroundStyle(IP.cream)
                .lineLimit(1)
            HStack(spacing: 5) {
                if let subIcon {
                    Image(systemName: subIcon).font(.system(size: 9))
                }
                Text(sub)
                    .lineLimit(1)
            }
            .font(.islandMono(10.5, .medium))
            .foregroundStyle(IP.cream(0.5))
            .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecordingTitle: View {
    let locality: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("正在录制语音 signal")
                .font(.islandDisplay(14, .semibold))
                .foregroundStyle(IP.cream)
                .lineLimit(1)
            HStack(spacing: 6) {
                Circle().fill(IP.rec).frame(width: 6, height: 6)
                Text("REC · \(locality)")
                    .font(.islandMono(10.5, .medium))
                    .foregroundStyle(IP.cream(0.5))
                    .textCase(.uppercase)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Compact + minimal accessories

private struct CompactLeading: View {
    let kind: SoloCompassActivityAttributes.Kind
    let state: SoloCompassActivityState

    var body: some View {
        switch kind {
        case .route:
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(IP.sunGold)
        case .countdown:
            Image(systemName: "person.2.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IP.sunGold)
        case .recording:
            Image(systemName: "mic.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IP.rec)
        case .compile:
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IP.sunGold)
        }
    }
}

private struct CompactTrailing: View {
    let kind: SoloCompassActivityAttributes.Kind
    let state: SoloCompassActivityState

    var body: some View {
        switch kind {
        case .route:
            HStack(spacing: 3) {
                Image(systemName: "figure.walk").font(.system(size: 11)).foregroundStyle(IP.cream(0.5))
                Text(state.etaText)
                    .font(.islandMono(13, .medium))
                    .foregroundStyle(IP.cream)
            }
        case .countdown:
            CountdownText(date: state.departureDate, font: .islandMono(13, .medium))
                .foregroundStyle(IP.sunGoldSoft)
        case .recording:
            DurationText(since: state.recordingStartDate, font: .islandMono(13, .medium))
                .foregroundStyle(IP.cream)
        case .compile:
            IslandCompileDots()
        }
    }
}

private struct MinimalGlyph: View {
    let kind: SoloCompassActivityAttributes.Kind
    let state: SoloCompassActivityState

    var body: some View {
        switch kind {
        case .route:
            Image(systemName: "location.north.circle.fill").foregroundStyle(IP.sunGold)
        case .countdown:
            Image(systemName: "person.2.fill").foregroundStyle(IP.sunGold)
        case .recording:
            Circle().fill(IP.rec).frame(width: 9, height: 9)
        case .compile:
            Image(systemName: "sparkles").foregroundStyle(IP.sunGold)
        }
    }
}

// MARK: - Expanded bottoms

private struct RouteBottom: View {
    let state: SoloCompassActivityState

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("下一站")
                        .font(.islandMono(10, .medium)).textCase(.uppercase)
                        .foregroundStyle(IP.sunGold)
                    Text(state.nextStopName)
                        .font(.islandDisplay(16, .semibold))
                        .foregroundStyle(IP.cream)
                        .lineLimit(1)
                    Text(state.nextStopMeta)
                        .font(.islandMono(11.5))
                        .foregroundStyle(IP.cream(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(state.etaText)
                        .font(.islandMono(22, .medium))
                        .foregroundStyle(IP.sunGoldSoft)
                    Text("预计到达")
                        .font(.islandMono(10)).textCase(.uppercase)
                        .foregroundStyle(IP.cream(0.5))
                }
            }
            IslandStopProgress(current: state.currentStopIndex, total: state.totalStops)
        }
    }
}

private struct CountdownBottom: View {
    let state: SoloCompassActivityState

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("距集合")
                        .font(.islandMono(10, .medium)).textCase(.uppercase)
                        .foregroundStyle(IP.sunGold)
                    CountdownText(date: state.departureDate, font: .islandMono(38, .medium))
                        .foregroundStyle(IP.cream)
                }
                Spacer()
                Label("已到达", systemImage: "checkmark")
                    .font(.islandDisplay(13, .semibold))
                    .foregroundStyle(IP.sunGoldSoft)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(IP.cream(0.1)))
                    .overlay(Capsule().stroke(IP.cream(0.16), lineWidth: 0.5))
            }
            HStack(spacing: 9) {
                IslandAvatarStack(initials: state.memberInitials)
                Text(state.memberSummary)
                    .font(.islandDisplay(12, .regular))
                    .foregroundStyle(IP.cream(0.5))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }
}

/// Shimmer skeleton rows for the compile scenario. Three rows of decreasing
/// width; when `progress >= 0` a gold fill shows how far synthesis has reached.
private struct CompileSkeleton: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ShimmerRow(widthFraction: 0.9, progress: progress)
            ShimmerRow(widthFraction: 0.7, progress: progress)
            ShimmerRow(widthFraction: 0.5, progress: progress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShimmerRow: View {
    let widthFraction: CGFloat
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            let trackW = geo.size.width * widthFraction
            ZStack(alignment: .leading) {
                Capsule().fill(IP.cream(0.1)).frame(width: trackW)
                if progress >= 0 {
                    Capsule().fill(IP.sunGold.opacity(0.55))
                        .frame(width: trackW * CGFloat(min(max(progress, 0), 1)))
                }
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Live timer helpers

/// Live count-DOWN to a future date, rendered as a mono mm:ss the OS ticks for us.
struct CountdownText: View {
    let date: Date?
    let font: Font

    var body: some View {
        if let date {
            Text(timerInterval: Date.now...max(date, Date.now.addingTimeInterval(1)),
                 countsDown: true)
                .font(font)
                .monospacedDigit()
        } else {
            Text("--:--").font(font)
        }
    }
}

/// Live count-UP from a start date (recording duration).
struct DurationText: View {
    let since: Date?
    let font: Font

    var body: some View {
        if let since {
            Text(timerInterval: since...Date.distantFuture, countsDown: false)
                .font(font)
                .monospacedDigit()
        } else {
            Text("0:00").font(font)
        }
    }
}

private struct CountdownPill: View {
    let date: Date?
    var body: some View {
        CountdownText(date: date, font: .islandMono(11, .medium))
            .foregroundStyle(IP.sunGoldSoft)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(IP.goldPill))
            .overlay(Capsule().stroke(IP.goldBorder, lineWidth: 1))
    }
}

private struct RecPill: View {
    let start: Date?
    var body: some View {
        DurationText(since: start, font: .islandMono(11, .medium))
            .foregroundStyle(IP.sunGoldSoft)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(IP.rec.opacity(0.18)))
            .overlay(Capsule().stroke(IP.rec.opacity(0.3), lineWidth: 1))
    }
}

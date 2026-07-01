import SwiftUI
import WidgetKit

/// The Lock Screen / banner presentation of the Live Activity (shown when the
/// device has no Dynamic Island, or below the clock on any device). Reuses the
/// same warm-amber chrome as the expanded island: a black glass card with a
/// gold-tinted icon tile, cream text, and mono numbers.
struct LockScreenLiveActivityView: View {
    let kind: SoloCompassActivityAttributes.Kind
    let state: SoloCompassActivityState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leadingTile
            VStack(alignment: .leading, spacing: 6) {
                header
                detail
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(14)
    }

    // MARK: leading icon tile

    @ViewBuilder private var leadingTile: some View {
        switch kind {
        case .recording:
            IslandIconTile(systemName: "mic.fill", fill: IP.recTile, tint: IP.rec, size: 38)
        case .route:
            IslandIconTile(systemName: "location.north.circle.fill", size: 38)
        case .countdown:
            IslandIconTile(systemName: "person.2.fill", size: 38)
        case .compile:
            IslandIconTile(systemName: "sparkles", size: 38)
        case .soloAgentHint:
            IslandIconTile(systemName: "sparkle", size: 38)
        case .timeCapsule:
            IslandIconTile(systemName: "hourglass", size: 38)
        case .dailyOmen:
            IslandIconTile(systemName: "sun.max.fill", size: 38)
        }
    }

    // MARK: header (app label + title)

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SOLOCOMPASS")
                .font(.islandMono(10, .medium))
                .tracking(1.4)
                .foregroundStyle(IP.cream(0.5))
            Text(titleText)
                .font(.islandDisplay(15, .semibold))
                .foregroundStyle(IP.cream)
                .lineLimit(1)
        }
    }

    private var titleText: String {
        switch kind {
        case .route:          return state.routeTitle
        case .countdown:      return state.groupTitle
        case .recording:      return "正在录制语音 signal"
        case .compile:        return state.compileTitle
        case .soloAgentHint:  return state.hintText.isEmpty ? "Solo 有个建议" : state.hintText
        case .timeCapsule:    return state.capsulePreview.isEmpty ? "有一个胶囊在等你" : state.capsulePreview
        case .dailyOmen:      return state.omenLine.isEmpty ? "今日的城市签" : state.omenLine
        }
    }

    // MARK: detail line(s)

    @ViewBuilder private var detail: some View {
        switch kind {
        case .route:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("下一站")
                        .font(.islandMono(9.5, .medium)).textCase(.uppercase)
                        .foregroundStyle(IP.sunGold)
                    Text(state.nextStopName)
                        .font(.islandDisplay(13, .semibold))
                        .foregroundStyle(IP.cream)
                        .lineLimit(1)
                }
                Text(state.nextStopMeta)
                    .font(.islandMono(11))
                    .foregroundStyle(IP.cream(0.5))
                    .lineLimit(1)
                IslandStopProgress(current: state.currentStopIndex, total: state.totalStops)
                    .frame(maxWidth: 160)
            }
        case .countdown:
            VStack(alignment: .leading, spacing: 6) {
                Label(state.meetPointName, systemImage: "mappin.and.ellipse")
                    .font(.islandMono(11))
                    .foregroundStyle(IP.cream(0.5))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    IslandAvatarStack(initials: state.memberInitials, size: 22)
                    Text(state.memberSummary)
                        .font(.islandDisplay(11.5))
                        .foregroundStyle(IP.cream(0.5))
                        .lineLimit(1)
                }
            }
        case .recording:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(IP.rec).frame(width: 6, height: 6)
                    Text("REC · \(state.recordingLocality)")
                        .font(.islandMono(10.5, .medium)).textCase(.uppercase)
                        .foregroundStyle(IP.cream(0.5))
                }
                IslandWaveform(samples: state.waveformSamples, barCount: 22, height: 22)
                    .frame(maxWidth: 180)
            }
        case .compile:
            Text(state.compileSubtitle)
                .font(.islandMono(11.5, .medium)).textCase(.uppercase)
                .foregroundStyle(IP.cream(0.5))
                .lineLimit(1)
        case .soloAgentHint:
            if !state.hintAnchorName.isEmpty {
                Label(state.hintAnchorName, systemImage: "mappin.and.ellipse")
                    .font(.islandMono(11))
                    .foregroundStyle(IP.cream(0.5))
                    .lineLimit(1)
            }
        case .timeCapsule:
            if !state.capsuleAnchorName.isEmpty {
                Label(state.capsuleAnchorName, systemImage: "hourglass")
                    .font(.islandMono(11))
                    .foregroundStyle(IP.cream(0.5))
                    .lineLimit(1)
            }
        case .dailyOmen:
            if !state.omenMicroTask.isEmpty {
                Label(state.omenMicroTask, systemImage: "checkmark.circle")
                    .font(.islandMono(11))
                    .foregroundStyle(IP.cream(0.5))
                    .lineLimit(1)
            }
        }
    }

    // MARK: trailing (live number)

    @ViewBuilder private var trailing: some View {
        switch kind {
        case .route:
            VStack(alignment: .trailing, spacing: 2) {
                Text(state.etaText)
                    .font(.islandMono(20, .medium))
                    .foregroundStyle(IP.sunGoldSoft)
                Text("ETA")
                    .font(.islandMono(9)).textCase(.uppercase)
                    .foregroundStyle(IP.cream(0.5))
            }
        case .countdown:
            CountdownText(date: state.departureDate, font: .islandMono(22, .medium))
                .foregroundStyle(IP.sunGoldSoft)
        case .recording:
            DurationText(since: state.recordingStartDate, font: .islandMono(18, .medium))
                .foregroundStyle(IP.cream)
        case .compile:
            IslandCompileDots()
        case .soloAgentHint, .timeCapsule, .dailyOmen:
            // Passive one-shot activities have no ticking number on the trailing edge.
            EmptyView()
        }
    }
}

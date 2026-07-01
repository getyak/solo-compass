import SwiftUI

/// Standalone preview of the 3 new Live Activity kinds (P2.2 #220):
/// soloAgentHint / timeCapsule / dailyOmen. Renders the lock-screen card
/// look inside the main app so the goal audit can screenshot each kind
/// without a real ActivityKit entitlement or a paired physical device.
///
/// Faithful to `LockScreenLiveActivityView` in `SoloCompassWidgets` —
/// same 3-column layout (icon tile / title+detail / trailing meta) and
/// same warm-amber CT tokens. Not a duplicate of the widget's render:
/// the widget target is not linkable from the main app, and this file
/// only powers the audit hub — the real activity still ships from
/// `SoloCompassWidgets`.
public struct LiveActivityLockScreenPreview: View {

    public let kind: SoloCompassActivityAttributes.Kind
    public let state: SoloCompassActivityState

    public init(kind: SoloCompassActivityAttributes.Kind, state: SoloCompassActivityState) {
        self.kind = kind
        self.state = state
    }

    public var body: some View {
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
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
    }

    // MARK: leading icon tile

    @ViewBuilder private var leadingTile: some View {
        switch kind {
        case .soloAgentHint: iconTile(symbol: "sparkle",       accent: CT.sunGoldDeep)
        case .timeCapsule:   iconTile(symbol: "hourglass",     accent: CT.capsuleGlow)
        case .dailyOmen:     iconTile(symbol: "sun.max.fill",  accent: CT.omenGold)
        default:             iconTile(symbol: "circle",        accent: CT.sunGold)
        }
    }

    private func iconTile(symbol: String, accent: Color) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(accent.opacity(0.22))
            .frame(width: 38, height: 38)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            )
    }

    // MARK: header

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SOLOCOMPASS")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color(white: 0.85).opacity(0.5))
            Text(titleText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(white: 0.98))
                .lineLimit(1)
        }
    }

    private var titleText: String {
        switch kind {
        case .soloAgentHint: return "Solo · 一个想法"
        case .timeCapsule:   return "时空胶囊 · 就在附近"
        case .dailyOmen:     return "今日城市签"
        default:             return "SoloCompass"
        }
    }

    // MARK: detail

    @ViewBuilder private var detail: some View {
        switch kind {
        case .soloAgentHint:
            VStack(alignment: .leading, spacing: 2) {
                Text(state.hintText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.93))
                    .lineLimit(2)
                if !state.hintAnchorName.isEmpty {
                    Text(state.hintAnchorName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(CT.sunGoldSoft.opacity(0.85))
                }
            }
        case .timeCapsule:
            VStack(alignment: .leading, spacing: 2) {
                Text(state.capsulePreview)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.93))
                    .lineLimit(2)
                if !state.capsuleAnchorName.isEmpty {
                    Text(state.capsuleAnchorName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(CT.capsuleGlow.opacity(0.85))
                }
            }
        case .dailyOmen:
            VStack(alignment: .leading, spacing: 2) {
                Text(state.omenLine)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Color(white: 0.96))
                    .lineLimit(2)
                if !state.omenMicroTask.isEmpty {
                    Text("· \(state.omenMicroTask)")
                        .font(.system(size: 11))
                        .foregroundStyle(CT.omenGold.opacity(0.9))
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: trailing

    @ViewBuilder private var trailing: some View {
        switch kind {
        case .soloAgentHint:
            Image(systemName: "arrow.up.forward.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(CT.sunGoldDeep)
        case .timeCapsule:
            Image(systemName: "envelope.fill")
                .font(.system(size: 20))
                .foregroundStyle(CT.capsuleGlow)
        case .dailyOmen:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20))
                .foregroundStyle(CT.omenGold)
        default:
            EmptyView()
        }
    }
}

/// Compact stack rendering all 3 new-kind previews on one screen so a
/// single simctl screenshot captures the P2.2 visual contract.
public struct LiveActivityAllKindsPreview: View {
    public init() {}
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Live Activity · 3 new kinds")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(CT.fgPrimary)

                Text("soloAgentHint")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CT.fgMuted)
                LiveActivityLockScreenPreview(
                    kind: .soloAgentHint,
                    state: SoloCompassActivityState(
                        hintText: "河堤傍晚人不多，要不要去坐一会",
                        hintAnchorName: "湄公河河堤"
                    )
                )

                Text("timeCapsule")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CT.fgMuted)
                LiveActivityLockScreenPreview(
                    kind: .timeCapsule,
                    state: SoloCompassActivityState(
                        capsulePreview: "半年前的自己给现在的你留了一句…",
                        capsuleAnchorName: "One Nimman coffee window"
                    )
                )

                Text("dailyOmen")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CT.fgMuted)
                LiveActivityLockScreenPreview(
                    kind: .dailyOmen,
                    state: SoloCompassActivityState(
                        omenLine: "Sit where the light is thin.",
                        omenMicroTask: "Order the second cheapest coffee."
                    )
                )
            }
            .padding(20)
        }
        .background(Color(white: 0.98))
        .navigationTitle("LiveActivity · 3 kinds")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("All 3 kinds") {
    LiveActivityAllKindsPreview()
}

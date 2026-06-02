import SwiftUI

/// Custom marker icon, 44x44 tap target. The visual changes with marker state;
/// the surrounding circle is always the category color, plus state-specific
/// adornments (gold glow, checkmark, heart, countdown, footprint).
///
/// `confidenceLevel` (0–5) drives a visual downgrade: level <= 1 uses a
/// dashed border, 70% fill opacity, no shadow, and a smaller 28×28 dot,
/// so AI-generated entries (Epic C US-018) are clearly distinguishable
/// from curated content at a glance.
public struct MarkerIconView: View {
    let category: ExperienceCategory
    let state: ExperienceMarkerState
    let confidenceLevel: Int
    /// Selection is orthogonal to marker state (a completed pin can still be
    /// the selected one), so it lives outside `ExperienceMarkerState` as an
    /// independent flag. Defaults to false to keep every existing call site
    /// source-compatible.
    let isSelected: Bool
    /// US-035: true when the FilterBar's "Now" mode is active. When set, a
    /// `bestNow` marker grows an extra CT.accent ring so the filter pill and
    /// the map highlight read as the same gesture. No effect on other states.
    let nowFilterActive: Bool

    @Environment(\.themeService) private var themeService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var selectionPulse = false
    @State private var nowRingPulse = false

    public init(
        category: ExperienceCategory,
        state: ExperienceMarkerState,
        confidenceLevel: Int = 5,
        isSelected: Bool = false,
        nowFilterActive: Bool = false
    ) {
        self.category = category
        self.state = state
        self.confidenceLevel = confidenceLevel
        self.isSelected = isSelected
        self.nowFilterActive = nowFilterActive
    }

    /// US-035: a `bestNow` marker should show the extra "Now" sync ring only
    /// when the Now filter is active and the pin is a high-confidence best-now
    /// entry (low-confidence AI guesses don't earn the highlight, mirroring the
    /// existing pulse-ring suppression).
    var showsNowSyncRing: Bool {
        guard nowFilterActive, !isLowConfidence else { return false }
        if case .bestNow = state { return true }
        return false
    }

    /// US-043: the easing applied to the Now-sync highlight as it appears and
    /// disappears, so toggling the Now filter pill animates the map ring in/out
    /// instead of snapping. A short `.easeInOut` keeps the two UIs feeling like
    /// one coordinated gesture. Exposed as a constant so tests can assert the
    /// transition animation is wired up without rendering the view.
    static let nowSyncTransition: Animation = .easeInOut(duration: 0.2)

    /// True when this marker should render in "AI-generated, low
    /// confidence" mode. Currently fires only at level 0–1 (Epic A US-A1
    /// reserves level 1 for AI-synthesized OSM entries).
    var isLowConfidence: Bool { confidenceLevel <= 1 }

    public var body: some View {
        markerContent
            // US-035: Now-filter sync ring, layered behind the marker (and the
            // selection halo) so a best-now pin visibly "lights up" the moment
            // the Now pill is toggled, tying the two UIs together.
            .background(nowSyncRing)
            // US-043: ease the ring in/out as the Now filter toggles so the
            // highlight glides between states instead of popping. Deselecting
            // Now flips `showsNowSyncRing` to false, fading the ring away.
            .animation(Self.nowSyncTransition, value: showsNowSyncRing)
            // Selection halo + lift, orthogonal to (and layered behind) the
            // state adornments so any marker — completed, favorited, etc. —
            // can read as "selected". Spring tuned for a snappy-but-soft tap
            // confirmation (response 0.3 / damping 0.6, per issue #131).
            .background(selectionRing)
            .scaleEffect(isSelected ? 1.3 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .onChange(of: reduceMotion) { _, reduced in
                if reduced {
                    pulse = false
                    selectionPulse = false
                    nowRingPulse = false
                }
            }
    }

    /// US-035: extra CT.accent ring drawn around best-now markers while the
    /// Now filter is on. Solid stroke for the static base; an outward pulse on
    /// top (suppressed under Reduce Motion) so the highlight is alive but never
    /// competes with the gold best-now pulse.
    @ViewBuilder
    private var nowSyncRing: some View {
        if showsNowSyncRing {
            Circle()
                .strokeBorder(CT.accent, lineWidth: 2.5)
                .frame(width: 50, height: 50)

            if !reduceMotion {
                Circle()
                    .stroke(CT.accent.opacity(0.45), lineWidth: 2)
                    .frame(width: 50, height: 50)
                    .scaleEffect(nowRingPulse ? 1.5 : 1.0)
                    .opacity(nowRingPulse ? 0.0 : 0.7)
                    .animation(
                        .easeOut(duration: 1.6).repeatForever(autoreverses: false),
                        value: nowRingPulse
                    )
                    .onAppear { nowRingPulse = true }
                    .onDisappear { nowRingPulse = false }
            }
        }
    }

    @ViewBuilder
    private var markerContent: some View {
        if themeService.selectedOption == .obsidian {
            ObsidianDotGridMarker(accent: themeService.currentTheme.accent, state: state)
                .frame(width: 44, height: 44)
                .accessibilityLabel(Text(accessibilityLabel))
                .accessibilityIdentifier(accessibilityIdentifier)
        } else {
            defaultMarkerBody
        }
    }

    @ViewBuilder
    private var selectionRing: some View {
        if isSelected {
            Circle()
                .strokeBorder(themeService.currentTheme.accent, lineWidth: 3)
                .frame(width: 44, height: 44)

            // Outward pulse ring that fades as it expands, giving a gentle
            // "selected" beacon effect without competing with bestNow's ring.
            if !reduceMotion {
                Circle()
                    .stroke(themeService.currentTheme.accent.opacity(0.5), lineWidth: 2)
                    .frame(width: 44, height: 44)
                    .scaleEffect(selectionPulse ? 1.6 : 1.0)
                    .opacity(selectionPulse ? 0.0 : 0.8)
                    .animation(
                        .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                        value: selectionPulse
                    )
                    .onAppear { selectionPulse = true }
                    .onDisappear { selectionPulse = false }
            }
        }
    }

    @ViewBuilder
    private var defaultMarkerBody: some View {
        ZStack {
            // Pulse ring for "best now" (suppress on low-confidence — we
            // don't want AI-guessed entries imitating verified excitement)
            if case .bestNow = state, !isLowConfidence, !reduceMotion {
                Circle()
                    .fill(Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255).opacity(0.4))
                    .frame(width: 56, height: 56)
                    .scaleEffect(pulse ? 1.2 : 0.9)
                    .opacity(pulse ? 0.0 : 0.7)
                    .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: pulse)
                    .onAppear { pulse = true }
            }

            Circle()
                .fill(fillColor)
                .frame(width: dotSize, height: dotSize)
                .overlay(borderOverlay)
                .shadow(color: shadowColor, radius: shadowRadius)
                .opacity(opacity)

            Image(systemName: category.symbol)
                .font(iconFont)
                .foregroundStyle(.white)
                .opacity(opacity)

            adornment
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var dotSize: CGFloat { isLowConfidence ? 28 : 36 }
    private var iconFont: Font {
        isLowConfidence ? .caption.weight(.semibold) : .subheadline.weight(.semibold)
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if isLowConfidence {
            // Dashed white border so AI-generated pins read as
            // "tentative" before the user even taps.
            Circle()
                .strokeBorder(
                    Color.white,
                    style: StrokeStyle(lineWidth: 2, dash: [4, 3])
                )
        } else {
            Circle().stroke(.white, lineWidth: 2)
        }
    }

    private var fillColor: Color {
        switch state {
        case .bestNow: return Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255)
        case .completed, .footprinted: return category.color
        default: return category.color
        }
    }

    private var shadowColor: Color {
        switch state {
        case .bestNow: return Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255).opacity(0.6)
        default: return .black.opacity(0.2)
        }
    }

    private var shadowRadius: CGFloat {
        if isLowConfidence { return 0 }
        switch state {
        case .bestNow: return 8
        default: return 3
        }
    }

    private var opacity: Double {
        if case .completed = state { return 0.45 }
        if isLowConfidence { return 0.7 }
        return 1.0
    }

    @ViewBuilder
    private var adornment: some View {
        switch state {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(.white, .green)
                .offset(x: 12, y: 12)
        case .favorited:
            Image(systemName: "heart.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(3)
                .background(Circle().fill(.white))
                .offset(x: 12, y: -12)
        case .upcoming(let minutes):
            HStack(spacing: 2) {
                Image(systemName: "clock.fill")
                    .font(.caption2)
                Text(Self.upcomingLabel(minutes: minutes))
                    .font(.caption2.bold().monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(upcomingTint(minutes: minutes)))
            .offset(x: 12, y: -12)
        case .footprinted:
            Image(systemName: "figure.walk")
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(3)
                .background(Circle().fill(Color.gray))
                .offset(x: 12, y: 12)
        case .bestNow, .default:
            EmptyView()
        }
    }

    static func upcomingLabel(minutes: Int) -> String {
        let m = max(0, minutes)
        return m < 60 ? "\(m)m" : "\(m / 60)h"
    }

    private func upcomingTint(minutes: Int) -> Color {
        switch minutes {
        case ...15: return .red
        case ...45: return .orange
        default:    return Color.black.opacity(0.85)
        }
    }

    private var accessibilityLabel: String {
        let categoryName = category.localizedTitle
        let suffix: String
        switch state {
        case .bestNow:
            suffix = ", \(NSLocalizedString("marker.a11y.bestNow", comment: ""))"
        case .completed:
            suffix = ", \(NSLocalizedString("marker.a11y.completed", comment: ""))"
        case .favorited:
            suffix = ", \(NSLocalizedString("marker.a11y.favorited", comment: ""))"
        case .upcoming(let m):
            let fmt = NSLocalizedString("marker.a11y.upcoming", comment: "starts in %d minutes")
            suffix = ", \(String(format: fmt, m))"
        case .footprinted:
            suffix = ", \(NSLocalizedString("marker.a11y.footprinted", comment: ""))"
        case .default:
            suffix = ""
        }
        if isLowConfidence {
            return "\(categoryName)\(suffix), \(NSLocalizedString("marker.a11y.lowConfidence", comment: ""))"
        }
        return "\(categoryName)\(suffix)"
    }

    /// Stable identifier encoding the confidence tier, selection, and Now-sync
    /// highlight — used in unit tests to assert that low-confidence, normal,
    /// selected, and Now-highlighted markers produce distinguishable views.
    var accessibilityIdentifier: String {
        let confidence = isLowConfidence ? "low" : "normal"
        let selection = isSelected ? ".selected" : ""
        let nowSync = showsNowSyncRing ? ".nowsync" : ""
        return "marker.\(category.rawValue).\(state.identifierFragment).\(confidence)\(selection)\(nowSync)"
    }
}

// MARK: - Obsidian 5×5 dot-grid marker (US-039)

/// Glowing neon-green 5×5 dot grid rendered for the Obsidian theme.
private struct ObsidianDotGridMarker: View {
    let accent: Color
    let state: ExperienceMarkerState

    var body: some View {
        ZStack {
            let cols = 5
            let spacing: CGFloat = 5
            let dotR: CGFloat = state == .bestNow ? 2.5 : 1.8

            VStack(spacing: spacing) {
                ForEach(0..<cols, id: \.self) { _ in
                    HStack(spacing: spacing) {
                        ForEach(0..<cols, id: \.self) { _ in
                            Circle()
                                .fill(accent)
                                .frame(width: dotR * 2, height: dotR * 2)
                        }
                    }
                }
            }
            .shadow(color: accent.opacity(0.8), radius: state == .bestNow ? 6 : 3)
        }
    }
}

#Preview {
    let states: [(String, ExperienceMarkerState)] = [
        ("default", .default),
        ("bestNow", .bestNow),
        ("completed", .completed),
        ("favorited", .favorited),
        ("upcoming 47", .upcoming(minutes: 47)),
        ("footprinted", .footprinted),
    ]
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reduce Motion OFF").font(.caption.bold()).padding(.horizontal)
            ForEach(states, id: \.0) { name, state in
                HStack(spacing: 16) {
                    Text(name).frame(width: 120, alignment: .leading)
                    ForEach(ExperienceCategory.allCases) { cat in
                        MarkerIconView(category: cat, state: state)
                    }
                }
            }
            HStack(spacing: 16) {
                Text("selected").frame(width: 120, alignment: .leading)
                ForEach(ExperienceCategory.allCases) { cat in
                    MarkerIconView(category: cat, state: .default, isSelected: true)
                }
            }

            // US-035: best-now markers with the Now filter active — the extra
            // CT.accent ring ties the map highlight to the "Now" filter pill.
            HStack(spacing: 16) {
                Text("bestNow + Now filter").frame(width: 120, alignment: .leading)
                ForEach(ExperienceCategory.allCases) { cat in
                    MarkerIconView(category: cat, state: .bestNow, nowFilterActive: true)
                }
            }

            Divider().padding(.vertical, 4)

            Text("Reduce Motion ON (static)").font(.caption.bold()).padding(.horizontal)
            ForEach(states, id: \.0) { name, state in
                HStack(spacing: 16) {
                    Text(name).frame(width: 120, alignment: .leading)
                    ForEach(ExperienceCategory.allCases) { cat in
                        MarkerIconView(category: cat, state: state)
                    }
                }
            }
            HStack(spacing: 16) {
                Text("selected").frame(width: 120, alignment: .leading)
                ForEach(ExperienceCategory.allCases) { cat in
                    MarkerIconView(category: cat, state: .default, isSelected: true)
                }
            }
        }
        .padding()
    }
    .background(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255))
}

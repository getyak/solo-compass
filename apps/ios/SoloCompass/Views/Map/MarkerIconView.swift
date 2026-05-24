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
    /// Whether this marker is the currently selected experience. Drives a
    /// scale-up + accent ring so the user can see which pin they tapped.
    let isSelected: Bool

    @Environment(\.themeService) private var themeService
    @State private var pulse = false

    public init(
        category: ExperienceCategory,
        state: ExperienceMarkerState,
        confidenceLevel: Int = 5,
        isSelected: Bool = false
    ) {
        self.category = category
        self.state = state
        self.confidenceLevel = confidenceLevel
        self.isSelected = isSelected
    }

    /// True when this marker should render in "AI-generated, low
    /// confidence" mode. Currently fires only at level 0–1 (Epic A US-A1
    /// reserves level 1 for AI-synthesized OSM entries).
    var isLowConfidence: Bool { confidenceLevel <= 1 }

    public var body: some View {
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
    private var defaultMarkerBody: some View {
        ZStack {
            // Selection ring — a white-haloed accent circle behind the pin so
            // the tapped marker reads as "active" without changing its color.
            if isSelected {
                Circle()
                    .stroke(category.color, lineWidth: 3)
                    .background(Circle().fill(.white.opacity(0.9)))
                    .frame(width: 50, height: 50)
                    .shadow(color: category.color.opacity(0.5), radius: 6)
            }

            // Pulse ring for "best now" (suppress on low-confidence — we
            // don't want AI-guessed entries imitating verified excitement)
            if case .bestNow = state, !isLowConfidence {
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
        .scaleEffect(isSelected ? 1.3 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
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
            Text("\(minutes)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.black.opacity(0.85)))
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

    /// Stable identifier encoding the confidence tier — used in unit tests to assert
    /// that low-confidence and normal markers produce distinguishable views.
    var accessibilityIdentifier: String {
        "marker.\(category.rawValue).\(state.identifierFragment).\(isLowConfidence ? "low" : "normal")"
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
    return ScrollView {
        VStack(spacing: 16) {
            ForEach(states, id: \.0) { name, state in
                HStack(spacing: 16) {
                    Text(name).frame(width: 120, alignment: .leading)
                    ForEach(ExperienceCategory.allCases) { cat in
                        MarkerIconView(category: cat, state: state)
                    }
                }
            }
        }
        .padding()
    }
    .background(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255))
}

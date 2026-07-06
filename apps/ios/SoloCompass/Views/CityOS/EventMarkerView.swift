import SwiftUI

/// City OS v2 · 在地 event回流 map marker (PRD §5.3). A limited-time local
/// happening drawn on the map as a burnt-orange core with a slowly rotating
/// dashed "timer" ring — the ring reads as "this expires". Fully static under
/// Reduce Motion (the ring stops rotating; nothing else changes), so the marker
/// never animates for motion-sensitive users.
///
/// Lives on its OWN `Annotation` layer, never inside the clustered POI pipeline
/// (marker-count perf tests guard that boundary).
struct EventMarkerView: View {
    let event: CityEvent
    /// Scales the core up when this event is the one the user just tapped
    /// "在地图上看" for (or picked in chat), so it stands out on arrival.
    var isHighlighted: Bool = false
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    /// Explicit ring-animation override (tests pin both states); nil resolves
    /// from the environment's Reduce Motion value at render time.
    private let explicitAnimates: Bool?

    init(
        event: CityEvent,
        isHighlighted: Bool = false,
        animatesRing: Bool? = nil,
        onTap: @escaping () -> Void
    ) {
        self.event = event
        self.isHighlighted = isHighlighted
        self.explicitAnimates = animatesRing
        self.onTap = onTap
    }

    /// Ring animates only when motion is allowed and the caller didn't force it
    /// off. `explicitAnimates` (tests) overrides the environment.
    private var resolvedAnimates: Bool {
        explicitAnimates ?? !reduceMotion
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                markerBody
                tag
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isButton)
    }

    private var markerBody: some View {
        ZStack {
            // Rotating dashed timer ring — the "限时" signal.
            Circle()
                .strokeBorder(
                    CT.eventLimited,
                    style: StrokeStyle(lineWidth: 2, dash: [4, 3])
                )
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(resolvedAnimates && spinning ? 360 : 0))
                .animation(
                    resolvedAnimates
                        ? .linear(duration: 14).repeatForever(autoreverses: false)
                        : nil,
                    value: spinning
                )
                .onAppear { if resolvedAnimates { spinning = true } }

            // Solid core.
            Circle()
                .fill(CT.eventLimited)
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .overlay(
                    Image(systemName: Self.categoryIcon(for: event.category))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                )
                .scaleEffect(isHighlighted ? 1.15 : 1.0)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6),
                    value: isHighlighted
                )
        }
    }

    private var tag: some View {
        Text(event.limitedLabel ?? event.whenLabel)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(CT.eventLimited)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.white))
            .overlay(Capsule().strokeBorder(CT.eventLimited.opacity(0.4), lineWidth: 0.5))
            .fixedSize()
    }

    private var accessibilityLabel: String {
        String(
            format: NSLocalizedString("cityos.event.marker.a11y", comment: "Event marker: %1$@, %2$@"),
            event.name,
            event.limitedLabel ?? event.whenLabel
        )
    }

    /// Map an event category slug to an SF Symbol. Pure + static so it's unit
    /// testable and reused by chat/live cards. Every returned symbol is verified
    /// by `SFSymbolExistenceTests`; unknown categories fall back to "calendar".
    static func categoryIcon(for category: String?) -> String {
        switch category {
        case "culture":  return "theatermasks"
        case "market":   return "basket"
        case "wellness": return "figure.run"
        case "music":    return "music.note"
        case "sports":   return "sportscourt"
        case "food":     return "fork.knife"
        case "notice":   return "exclamationmark.triangle"
        default:         return "calendar"
        }
    }
}

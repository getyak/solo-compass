import SwiftUI
import CoreLocation

// MARK: - ActiveRoute

/// A route currently drawn on the map: the route itself plus its stops resolved
/// to coordinates in walking order. Held by `CompassMapContentView` and rendered
/// as a polyline + numbered pins; `nil` means no route is active.
struct ActiveRoute: Equatable {
    let route: Route
    let coordinates: [CLLocationCoordinate2D]

    static func == (lhs: ActiveRoute, rhs: ActiveRoute) -> Bool {
        lhs.route.id == rhs.route.id &&
        lhs.coordinates.count == rhs.coordinates.count &&
        zip(lhs.coordinates, rhs.coordinates).allSatisfy {
            $0.latitude == $1.latitude && $0.longitude == $1.longitude
        }
    }
}

// MARK: - RouteStopBadge

/// Numbered pin marking a stop's position along the active route. The number
/// reads the walking order at a glance.
struct RouteStopBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(CT.accent))
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .accessibilityLabel(Text(String(
                format: NSLocalizedString("route.active.stop.a11y", comment: "Route stop %d"),
                number
            )))
    }
}

// MARK: - ActiveRouteBanner

/// Top banner shown while a route is active. Walking glyph + title + stop count
/// + 3 mid-route controls (skip / pause / end). The skip and pause callbacks
/// are optional so older callsites that only pass `onEnd` keep compiling.
struct ActiveRouteBanner: View {
    let title: String
    let stopCount: Int
    var onSkip: (() -> Void)? = nil
    var onPause: (() -> Void)? = nil
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.walk")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CT.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(String(
                    format: NSLocalizedString("route.active.stops", comment: "N stops"),
                    stopCount
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let onSkip {
                circleButton(systemImage: "forward.end.fill",
                             a11y: NSLocalizedString("route.active.skip", comment: "Skip this stop"),
                             action: onSkip)
            }
            if let onPause {
                circleButton(systemImage: "pause.fill",
                             a11y: NSLocalizedString("route.active.pause", comment: "Pause route"),
                             action: onPause)
            }
            circleButton(systemImage: "xmark",
                         a11y: NSLocalizedString("route.active.end", comment: "End route"),
                         action: onEnd)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func circleButton(systemImage: String, a11y: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(a11y))
    }
}

#Preview("ActiveRouteBanner") {
    ActiveRouteBanner(title: "湄公河日落散步", stopCount: 3,
                      onSkip: {}, onPause: {}, onEnd: {})
        .padding()
}

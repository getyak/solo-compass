import CoreLocation
import SwiftUI
import UIKit

// MARK: - RouteShareCardView (dispatcher)

/// 1080×1920 portrait share card for a route. Dispatches on `style`:
///   - `.map`   → `RouteMapCard` (needs a pre-rendered `basemap` snapshot)
///   - `.trace` → `RouteTraceCard` (pure vector, no basemap)
///   - else     → `RouteGradientCard` (legacy fallback when no coordinates)
///
/// Laid out at half-pixel `renderSize`; `ImageRenderer` scales up by `renderScale`.
/// Uses plain `VStack`/`ZStack` only — `ImageRenderer` does not expand
/// Lazy/Scroll containers.
struct RouteShareCardView: View {
    let payload: RouteSharePayload
    let style: RouteShareStyle
    /// Pre-rendered MapKit basemap (only used by `.map`). Nil → map card falls
    /// back to the trace look so the card is never blank.
    var basemap: UIImage? = nil

    static let renderSize = CGSize(width: 540, height: 960)
    static let renderScale: CGFloat = 2.0

    var body: some View {
        Group {
            if style == .map, let basemap, payload.hasAnyCoordinate {
                RouteMapCard(payload: payload, basemap: basemap)
            } else if (style == .map || style == .trace), payload.hasAnyCoordinate {
                RouteTraceCard(payload: payload)
            } else {
                RouteGradientCard(payload: payload)
            }
        }
        .frame(width: Self.renderSize.width, height: Self.renderSize.height)
    }
}

// MARK: - Shared sub-components

/// Top brand strip: compass mark + product name on the left, place on the right.
private struct ShareBrandStrip: View {
    let placeLabel: String

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Text("🧭").font(.system(size: 26))
                Text(NSLocalizedString("route.share.kicker", comment: "Route share card kicker"))
                    .font(.system(size: 16, weight: .bold))
                    .tracking(2)
                    .textCase(.uppercase)
            }
            Spacer()
            if !placeLabel.isEmpty {
                Label(placeLabel, systemImage: "mappin.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white.opacity(0.95))
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.28))
    }
}

/// Bottom text block: title, summary, stat chips, walked-by, tags, brand handle.
private struct ShareTextBlock: View {
    let payload: RouteSharePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(payload.title)
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)

            if !payload.summary.isEmpty {
                Text(payload.summary)
                    .font(.system(size: 21))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            statRow

            if payload.walkedByCount > 0 {
                let fmt = NSLocalizedString("route.share.walkedBy", comment: "walked-by social proof")
                Text(String(format: fmt, payload.walkedByCount))
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }

            if !payload.tags.isEmpty {
                HStack(spacing: 8) {
                    ForEach(payload.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 17, weight: .semibold))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.white.opacity(0.2)))
                            .foregroundStyle(.white)
                    }
                }
            }

            Text(payload.brandHandle)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.top, 2)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statRow: some View {
        HStack(spacing: 10) {
            statChip(icon: "clock.fill", value: "\(payload.durationMinutes)",
                     unit: NSLocalizedString("route.share.min", comment: "minutes unit"))
            statChip(icon: "ruler.fill", value: payload.distanceLabel, unit: "")
            statChip(icon: "figure.walk", value: "\(payload.stopCount)",
                     unit: NSLocalizedString("route.share.stops", comment: "stops unit"))
        }
    }

    private func statChip(icon: String, value: String, unit: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
            Text(value).font(.system(size: 20, weight: .bold))
            if !unit.isEmpty {
                Text(unit).font(.system(size: 15, weight: .medium)).opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(.white.opacity(0.22)))
    }
}

/// The route polyline drawn with a white halo + accent core, plus numbered stop
/// badges. Reused as an overlay by both the map card and the trace card.
private struct RoutePolylineOverlay: View {
    let coordinates: [CLLocationCoordinate2D]
    var lineWidth: CGFloat = 8
    var haloWidth: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let stops = RouteNormalizer.stopPoints(in: rect, coordinates: coordinates)

            ZStack {
                if coordinates.count >= 2 {
                    RoutePolylineShape(coordinates: coordinates)
                        .stroke(.white, style: StrokeStyle(lineWidth: haloWidth, lineCap: .round, lineJoin: .round))
                    RoutePolylineShape(coordinates: coordinates)
                        .stroke(CT.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array(stops.enumerated()), id: \.offset) { index, point in
                    StopBadge(number: index + 1, isFirst: index == 0, isLast: index == stops.count - 1)
                        .position(point)
                }
            }
        }
    }
}

/// White circular badge with the stop number; start/end get a tinted ring.
private struct StopBadge: View {
    let number: Int
    var isFirst: Bool = false
    var isLast: Bool = false

    var body: some View {
        Text("\(number)")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(CT.accent)
            .frame(width: 32, height: 32)
            .background(Circle().fill(.white))
            .overlay(
                Circle().stroke(ringColor, lineWidth: isFirst || isLast ? 3 : 0)
            )
            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
    }

    private var ringColor: Color {
        if isFirst { return .green }
        if isLast { return .red }
        return .clear
    }
}

// MARK: - RouteMapCard

/// Real street basemap with the route polyline + numbered stops on top.
private struct RouteMapCard: View {
    let payload: RouteSharePayload
    let basemap: UIImage

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(uiImage: basemap)
                .resizable()
                .scaledToFill()
                .clipped()

            RoutePolylineOverlay(coordinates: payload.coordinates)

            LinearGradient(
                colors: [.clear, .black.opacity(0.2), .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                ShareBrandStrip(placeLabel: payload.placeLabel)
                Spacer(minLength: 0)
                ShareTextBlock(payload: payload)
            }
        }
    }
}

// MARK: - RouteTraceCard

/// No basemap: the polyline is drawn as a pure vector stroke over the category
/// gradient. The fallback target when a snapshot can't be produced.
private struct RouteTraceCard: View {
    let payload: RouteSharePayload

    var body: some View {
        ZStack(alignment: .bottom) {
            CategoryVisual.gradient(for: payload.category)

            TraceGridBackground()
                .opacity(0.10)

            RoutePolylineOverlay(coordinates: payload.coordinates)
                .padding(.top, 90)
                .padding(.bottom, 360)
                .padding(.horizontal, 24)

            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                ShareBrandStrip(placeLabel: payload.placeLabel)
                Spacer(minLength: 0)
                ShareTextBlock(payload: payload)
            }
        }
    }
}

/// Subtle grid backdrop for the trace card so empty space reads as "a map".
private struct TraceGridBackground: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let step: CGFloat = 48
                var x: CGFloat = 0
                while x <= geo.size.width {
                    path.move(to: .init(x: x, y: 0))
                    path.addLine(to: .init(x: x, y: geo.size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y <= geo.size.height {
                    path.move(to: .init(x: 0, y: y))
                    path.addLine(to: .init(x: geo.size.width, y: y))
                    y += step
                }
            }
            .stroke(.white, lineWidth: 0.5)
        }
    }
}

// MARK: - RouteGradientCard (legacy fallback)

/// The original gradient-only card. Used when there are no usable coordinates.
private struct RouteGradientCard: View {
    let payload: RouteSharePayload

    var body: some View {
        ZStack(alignment: .bottom) {
            CategoryVisual.gradient(for: payload.category)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Text(CategoryVisual.emoji(for: payload.category)).font(.system(size: 60))
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                Spacer(minLength: 0)
                ShareTextBlock(payload: payload)
            }
        }
    }
}

// MARK: - Previews

#Preview("Trace") {
    RouteShareCardView(payload: .preview, style: .trace)
        .scaleEffect(0.4)
}

#Preview("Gradient fallback") {
    RouteShareCardView(payload: .previewNoCoords, style: .map)
        .scaleEffect(0.4)
}

extension RouteSharePayload {
    static var preview: RouteSharePayload {
        RouteSharePayload(
            title: "黄昏河岸慢走",
            summary: "从老城咖啡馆出发，沿河散步到日落观景台。",
            placeLabel: "Bangkok",
            category: .coffee,
            durationMinutes: 120,
            distanceMeters: 2400,
            paceLabel: "Relaxed",
            stopCount: 5,
            walkedByCount: 37,
            tags: ["sunset", "riverside", "coffee"],
            coordinates: [
                .init(latitude: 13.7460, longitude: 100.4980),
                .init(latitude: 13.7510, longitude: 100.5030),
                .init(latitude: 13.7490, longitude: 100.5100),
                .init(latitude: 13.7440, longitude: 100.5140),
                .init(latitude: 13.7400, longitude: 100.5120),
            ]
        )
    }

    static var previewNoCoords: RouteSharePayload {
        RouteSharePayload(
            title: "黄昏河岸慢走",
            summary: "从老城咖啡馆出发。",
            placeLabel: "Bangkok",
            category: .coffee,
            durationMinutes: 120,
            distanceMeters: 2400,
            paceLabel: "Relaxed",
            stopCount: 5,
            walkedByCount: 37,
            tags: ["sunset"],
            coordinates: []
        )
    }
}

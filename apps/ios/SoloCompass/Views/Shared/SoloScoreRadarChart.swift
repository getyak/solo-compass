import SwiftUI

/// Radar chart visualising the six SoloScore dimensions.
/// Falls back to highlighted progress bars when dimension variance < 0.5.
public struct SoloScoreRadarChart: View {
    let score: SoloScore

    @State private var drawProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let axes: [(label: String, symbol: String, keyPath: KeyPath<SoloScore.Breakdown, Double>)] = [
        (NSLocalizedString("solo.seating",    comment: ""), "chair",              \.seatingFriendly),
        (NSLocalizedString("solo.staff",      comment: ""), "person.crop.circle", \.staffPressure),
        (NSLocalizedString("solo.wifi",       comment: ""), "wifi",               \.soloPatronRatio),
        (NSLocalizedString("solo.noise",      comment: ""), "speaker.slash",      \.ambianceFit),
        (NSLocalizedString("solo.safety",     comment: ""), "shield",             \.safety),
        (NSLocalizedString("solo.portioning", comment: ""), "fork.knife",         \.soloPortioning),
    ]

    private var values: [Double] {
        Self.axes.map { score.breakdown[keyPath: $0.keyPath] }
    }

    private var variance: Double {
        let vals = values
        let mean = vals.reduce(0, +) / Double(vals.count)
        let squaredDiffs = vals.map { ($0 - mean) * ($0 - mean) }
        return squaredDiffs.reduce(0, +) / Double(vals.count)
    }

    public init(score: SoloScore) {
        self.score = score
    }

    public var body: some View {
        Group {
            if variance >= 0.5 {
                radarChart
            } else {
                fallbackBars
            }
        }
        .onAppear {
            if reduceMotion {
                drawProgress = 1
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) {
                    drawProgress = 1
                }
            }
        }
    }

    // MARK: - Radar

    private var radarChart: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let axisCount = Self.axes.count
            let radius = size * 0.38

            ZStack {
                // Grid rings
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { fraction in
                    radarPolygon(
                        center: center,
                        radius: radius * fraction,
                        count: axisCount,
                        values: Array(repeating: 1.0, count: axisCount)
                    )
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                }

                // Axis spokes
                ForEach(0..<axisCount, id: \.self) { i in
                    let angle = axisAngle(index: i, count: axisCount)
                    let tip = point(center: center, radius: radius, angle: angle)
                    Path { p in
                        p.move(to: center)
                        p.addLine(to: tip)
                    }
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }

                // Data polygon (scaled by drawProgress for entrance animation)
                radarPolygon(center: center, radius: radius, count: axisCount, values: values.map { $0 / 10.0 * drawProgress })
                    .fill(score.scoreColor.opacity(0.15))

                radarPolygon(center: center, radius: radius, count: axisCount, values: values.map { $0 / 10.0 * drawProgress })
                    .stroke(score.scoreColor, lineWidth: 2)

                // Axis labels with SF Symbol icons
                ForEach(0..<axisCount, id: \.self) { i in
                    let angle = axisAngle(index: i, count: axisCount)
                    let labelRadius = radius + size * 0.14
                    let pos = point(center: center, radius: labelRadius, angle: angle)
                    let axis = Self.axes[i]

                    VStack(spacing: 2) {
                        Image(systemName: axis.symbol)
                            .font(.system(size: size * 0.065))
                            .foregroundStyle(score.scoreColor)
                        Text(String(format: "%.0f", values[i]))
                            .font(.system(size: size * 0.055, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    .position(pos)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(radarAccessibilityLabel)
    }

    private func radarPolygon(center: CGPoint, radius: CGFloat, count: Int, values: [Double]) -> Path {
        Path { path in
            for i in 0..<count {
                let angle = axisAngle(index: i, count: count)
                let r = radius * CGFloat(max(0, min(1, values[i])))
                let pt = point(center: center, radius: r, angle: angle)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.closeSubpath()
        }
    }

    private func axisAngle(index: Int, count: Int) -> Double {
        // Start at top (−π/2) and go clockwise
        Double(index) / Double(count) * 2 * .pi - .pi / 2
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
    }

    private var radarAccessibilityLabel: Text {
        let descriptions = zip(Self.axes, values).map { axis, val in
            "\(axis.label): \(Int(val))"
        }.joined(separator: ", ")
        return Text(NSLocalizedString("solo.radar.a11y", comment: "") + ": " + descriptions)
    }

    // MARK: - Fallback bars

    private var fallbackBars: some View {
        VStack(spacing: 8) {
            ForEach(0..<Self.axes.count, id: \.self) { i in
                let axis = Self.axes[i]
                let val = values[i]
                HStack(spacing: 8) {
                    Image(systemName: axis.symbol)
                        .font(.caption)
                        .foregroundStyle(score.scoreColor)
                        .frame(width: 20)
                    Text(axis.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.gray.opacity(0.15))
                            Capsule()
                                .fill(score.scoreColor)
                                .frame(width: geo.size.width * (val / 10.0) * drawProgress)
                        }
                    }
                    .frame(height: 6)
                    Text(String(format: "%.0f", val))
                        .font(.caption.monospacedDigit())
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
    }
}

#Preview("High Variance — Radar") {
    let highVariance = SoloScore(
        overall: 7.8,
        breakdown: .init(
            seatingFriendly: 9,
            soloPatronRatio: 3,
            staffPressure: 9,
            soloPortioning: 8,
            ambianceFit: 2,
            safety: 9
        ),
        hint: "Great seating and safety, but noisy and few solo patrons.",
        basedOnCount: 22
    )
    return VStack(spacing: 24) {
        Text("Radar Chart (high variance)")
            .font(.headline)
        SoloScoreRadarChart(score: highVariance)
            .frame(width: 280, height: 280)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Low Variance — Fallback Bars") {
    let lowVariance = SoloScore(
        overall: 9.2,
        breakdown: .init(
            seatingFriendly: 9,
            soloPatronRatio: 9,
            staffPressure: 9,
            soloPortioning: 9,
            ambianceFit: 9,
            safety: 9
        ),
        hint: "Consistently excellent across all dimensions.",
        basedOnCount: 14
    )
    return VStack(spacing: 24) {
        Text("Fallback Bars (low variance)")
            .font(.headline)
        SoloScoreRadarChart(score: lowVariance)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    .padding()
}

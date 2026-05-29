import SwiftUI

/// Radar chart visualising the six SoloScore dimensions.
/// Falls back to highlighted progress bars when dimension variance < 0.5.
/// Tap the chart to replay the draw-in animation (Reduce Motion: no replay, no haptic).
public struct SoloScoreRadarChart: View {
    let score: SoloScore

    @State private var drawProgress: Double = 0
    @State private var isReplaying: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let haptic = UIImpactFeedbackGenerator(style: .soft)
    private static let springDuration: Double = 0.7

    private static let axes: [(label: String, symbol: String, keyPath: KeyPath<SoloScore.Breakdown, Double>)] = [
        (NSLocalizedString("solo.seating",    comment: ""), "chair",              \.seatingFriendly),
        (NSLocalizedString("solo.staff",      comment: ""), "person.crop.circle", \.staffPressure),
        (NSLocalizedString("solo.patrons",    comment: ""), "person.2",           \.soloPatronRatio),
        (NSLocalizedString("solo.ambiance",   comment: ""), "sparkles",           \.ambianceFit),
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

    private var weakestIndex: Int {
        values.indices.min(by: { values[$0] < values[$1] }) ?? 0
    }

    // Amber accent matching the app's accentGold
    private static let amberAccent = Color(red: 0xD4 / 255, green: 0xA8 / 255, blue: 0x43 / 255)

    public init(score: SoloScore) {
        self.score = score
    }

    public var body: some View {
        VStack(spacing: 8) {
            Group {
                if variance >= 0.5 {
                    radarChart
                } else {
                    fallbackBars
                }
            }

            weakestCaption
        }
        .onAppear {
            if reduceMotion {
                drawProgress = 1
            } else {
                withAnimation(.spring(response: Self.springDuration, dampingFraction: 0.75)) {
                    drawProgress = 1
                }
                haptic.prepare()
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.springDuration) {
                    haptic.impactOccurred()
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
                // Grid rings (static scaffold)
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { fraction in
                    radarPolygon(
                        center: center,
                        radius: radius * fraction,
                        count: axisCount,
                        values: Array(repeating: 1.0, count: axisCount)
                    )
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                }

                // Axis spokes (static scaffold)
                ForEach(0..<axisCount, id: \.self) { i in
                    let angle = axisAngle(index: i, count: axisCount)
                    let tip = point(center: center, radius: radius, angle: angle)
                    Path { p in
                        p.move(to: center)
                        p.addLine(to: tip)
                    }
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }

                // Data polygon — grows from center as drawProgress goes 0 → 1
                let animatedValues = values.map { ($0 / 10.0) * drawProgress }

                radarPolygon(center: center, radius: radius, count: axisCount, values: animatedValues)
                    .fill(score.scoreColor.opacity(0.15))

                radarPolygon(center: center, radius: radius, count: axisCount, values: animatedValues)
                    .stroke(score.scoreColor, lineWidth: 2)

                // Vertex dots — one per dimension, grow in sync with drawProgress
                ForEach(0..<axisCount, id: \.self) { i in
                    let angle = axisAngle(index: i, count: axisCount)
                    let isWeakest = i == weakestIndex
                    let dotRadius = size * 0.018 * (isWeakest ? 1.3 : 1.0)
                    let dotPos = point(
                        center: center,
                        radius: radius * CGFloat(values[i] / 10.0) * CGFloat(drawProgress),
                        angle: angle
                    )
                    Circle()
                        .fill(isWeakest ? Self.amberAccent : score.scoreColor)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                        .frame(width: dotRadius * 2, height: dotRadius * 2)
                        .scaleEffect(drawProgress)
                        .position(dotPos)
                        .accessibilityHidden(true)
                }

                // Axis labels with SF Symbol icons — stagger-fade per axis
                ForEach(0..<axisCount, id: \.self) { i in
                    let angle = axisAngle(index: i, count: axisCount)
                    let labelRadius = radius + size * 0.14
                    let pos = point(center: center, radius: labelRadius, angle: angle)
                    let axis = Self.axes[i]
                    let isWeakest = i == weakestIndex
                    let labelDelay = Double(i) * 0.06
                    let labelOpacity = max(0, min(1, (drawProgress - labelDelay) / (1.0 - labelDelay)))

                    VStack(spacing: 2) {
                        Image(systemName: axis.symbol)
                            .font(.system(size: size * 0.065))
                            .foregroundStyle(isWeakest ? Self.amberAccent : score.scoreColor)
                        // Always display final values — animation only affects opacity
                        Text(String(format: "%.0f", values[i]))
                            .font(.system(size: size * 0.055, weight: isWeakest ? .bold : .semibold, design: .rounded))
                            .foregroundStyle(isWeakest ? Self.amberAccent : Color.primary)
                    }
                    .opacity(labelOpacity)
                    .position(pos)
                    .accessibilityHidden(true) // covered by radarAccessibilityLabel below
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(radarAccessibilityLabel)
        .accessibilityHint(reduceMotion ? Text("") : Text(NSLocalizedString("solo.radar.replayHint", comment: "Tap to replay the draw-in animation")))
        .onTapGesture {
            guard !reduceMotion, !isReplaying else { return }
            replay()
        }
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
        let overallFormatted = String(format: "%.1f", score.overall)
        let overallLabel = String(format: NSLocalizedString("solo.a11y", comment: ""), overallFormatted)

        let sortedDimensions = zip(Self.axes, values)
            .sorted { $0.1 > $1.1 }
        let dimensionParts = sortedDimensions.map { axis, val in
            "\(axis.label) \(Int(val)) of 10"
        }.joined(separator: ", ")

        var label = "\(overallLabel). \(dimensionParts)."

        if values[weakestIndex] < 6 {
            let weakestName = Self.axes[weakestIndex].label
            let weakestSentence = String(
                format: NSLocalizedString("solo.radar.weakest.a11y", comment: ""),
                weakestName
            )
            label += " \(weakestSentence)"
        }

        return Text(label)
    }

    // MARK: - Replay

    private func replay() {
        isReplaying = true
        drawProgress = 0
        withAnimation(.spring(response: Self.springDuration, dampingFraction: 0.75)) {
            drawProgress = 1
        }
        haptic.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.springDuration) {
            haptic.impactOccurred()
            isReplaying = false
        }
    }

    // MARK: - Honest-tradeoff caption

    // Renders for both radar and fallback-bars paths via body's shared VStack.
    // Fixed-min-height container prevents layout jump during fade-in.
    @ViewBuilder private var weakestCaption: some View {
        let captionVisible = values[weakestIndex] < 6
        ZStack {
            if captionVisible {
                let captionText = String(
                    format: NSLocalizedString("solo.radar.weakest", comment: ""),
                    Self.axes[weakestIndex].label
                )
                Label(captionText, systemImage: "exclamationmark.bubble")
                    .font(.caption)
                    .foregroundStyle(Self.amberAccent)
                    .opacity(drawProgress >= 0.99 ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeIn(duration: 0.3), value: drawProgress >= 0.99)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: captionVisible ? 20 : 0)
    }

    // MARK: - Fallback bars

    private var fallbackBars: some View {
        VStack(spacing: 8) {
            ForEach(0..<Self.axes.count, id: \.self) { i in
                let axis = Self.axes[i]
                let val = values[i]
                let isWeakest = i == weakestIndex
                let barDelay = Double(i) * 0.06
                let barProgress = max(0, min(1, (drawProgress - barDelay) / (1.0 - barDelay)))
                HStack(spacing: 8) {
                    Image(systemName: axis.symbol)
                        .font(.caption)
                        .foregroundStyle(isWeakest ? Self.amberAccent : score.scoreColor)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(axis.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                        .accessibilityHidden(true)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.gray.opacity(0.15))
                                .accessibilityHidden(true)
                            Capsule()
                                .fill(score.scoreColor)
                                .frame(width: geo.size.width * (val / 10.0) * barProgress)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(height: 6)
                    Text(String(format: "%.0f", val))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isWeakest ? Self.amberAccent : Color.primary)
                        .fontWeight(isWeakest ? .bold : .regular)
                        .frame(width: 24, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(radarAccessibilityLabel)
        .accessibilityHint(reduceMotion ? Text("") : Text(NSLocalizedString("solo.radar.replayHint", comment: "")))
        .onTapGesture {
            guard !reduceMotion, !isReplaying else { return }
            replay()
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
    VStack(spacing: 24) {
        Text("Radar Chart (high variance) — tap to replay, dots at vertices")
            .font(.headline)
            .multilineTextAlignment(.center)
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
    VStack(spacing: 24) {
        Text("Fallback Bars (low variance, no weak dim) — no amber caption")
            .font(.headline)
            .multilineTextAlignment(.center)
        SoloScoreRadarChart(score: lowVariance)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    .padding()
}

#Preview("Low Variance — Fallback Bars + Weak Dim") {
    let lowVarianceWeak = SoloScore(
        overall: 7.5,
        breakdown: .init(
            seatingFriendly: 9,
            soloPatronRatio: 9,
            staffPressure: 9,
            soloPortioning: 9,
            ambianceFit: 4,
            safety: 9
        ),
        hint: "Great across most dims but ambiance is a weak point.",
        basedOnCount: 11
    )
    VStack(spacing: 24) {
        Text("Fallback Bars (low variance, weak ambiance) — amber caption")
            .font(.headline)
            .multilineTextAlignment(.center)
        SoloScoreRadarChart(score: lowVarianceWeak)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    .padding()
}

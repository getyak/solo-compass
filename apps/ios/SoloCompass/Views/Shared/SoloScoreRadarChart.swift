import SwiftUI
import Accessibility

/// Radar chart visualising the six SoloScore dimensions.
/// Falls back to highlighted progress bars when dimension variance < 0.5.
/// Tap the chart to replay the draw-in animation (Reduce Motion: no replay, no haptic).
/// Tap any axis label to see a plain-language tooltip for that dimension.
public struct SoloScoreRadarChart: View {
    let score: SoloScore

    @State private var drawProgress: Double = 0
    @State private var isReplaying: Bool = false
    @State private var selectedAxis: Int? = nil
    @State private var tooltipDismissTask: Task<Void, Never>? = nil
    @State private var showReplayHint: Bool = false
    @AppStorage("radar.replayHintSeen") private var replayHintSeen: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let springDuration: Double = 0.7
    private static let tooltipAutoDismissSeconds: Double = 4

    private static let axes: [(label: String, symbol: String, keyPath: KeyPath<SoloScore.Breakdown, Double>, descKey: String)] = [
        (NSLocalizedString("solo.seating",    comment: ""), "chair",              \.seatingFriendly, "solo.seating.desc"),
        (NSLocalizedString("solo.staff",      comment: ""), "person.crop.circle", \.staffPressure,   "solo.staff.desc"),
        (NSLocalizedString("solo.patrons",    comment: ""), "person.2",           \.soloPatronRatio, "solo.patrons.desc"),
        (NSLocalizedString("solo.ambiance",   comment: ""), "sparkles",           \.ambianceFit,     "solo.ambiance.desc"),
        (NSLocalizedString("solo.safety",     comment: ""), "shield",             \.safety,          "solo.safety.desc"),
        (NSLocalizedString("solo.portioning", comment: ""), "fork.knife",         \.soloPortioning,  "solo.portioning.desc"),
    ]

    private var values: [Double] {
        Self.axes.map { score.breakdown[keyPath: $0.keyPath] }
    }

    private func animatedValue(_ raw: Double) -> Int {
        Int((raw * drawProgress).rounded())
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

    private var strongestIndex: Int {
        values.indices.max(by: { values[$0] < values[$1] }) ?? 0
    }

    // True only when the top dimension qualifies as a genuine strength
    private var hasQualifyingStrongest: Bool {
        let si = strongestIndex
        return values[si] >= 8 && si != weakestIndex
    }

    // Amber accent matching the app's accentGold
    private static let amberAccent = Color(red: 0xD4 / 255, green: 0xA8 / 255, blue: 0x43 / 255)
    private static let greenAccent = Color.green

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
            .accessibilityAction(named: Text(NSLocalizedString("solo.radar.replay.a11y", comment: ""))) {
                guard !reduceMotion else { return }
                replay()
            }

            weakestCaption

            if showReplayHint {
                Label(NSLocalizedString("solo.radar.replay.hint", comment: ""), systemImage: "arrow.clockwise")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                    .accessibilityHidden(true)
            }

            if let idx = selectedAxis {
                axisDimensionTooltip(for: idx)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .scale(scale: 0.92).combined(with: .opacity)
                    )
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.75), value: selectedAxis)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.75), value: selectedAxis)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.75), value: showReplayHint)
        .onAppear {
            if reduceMotion {
                drawProgress = 1
            } else {
                withAnimation(.spring(response: Self.springDuration, dampingFraction: 0.75)) {
                    drawProgress = 1
                }
                // Route through HapticService so the user's haptics opt-out is respected.
                HapticService.shared.prepare(style: .soft)
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.springDuration) {
                    Haptics.impact(.soft)
                    if !replayHintSeen && !isReplaying {
                        showReplayHint = true
                        replayHintSeen = true
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            withAnimation { showReplayHint = false }
                        }
                    }
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
                // Summary accessibility element — VoiceOver lands here first
                Rectangle().fill(.clear).frame(height: 0)
                    .accessibilityElement()
                    .accessibilityLabel(radarAccessibilityLabel)
                    .accessibilityValue(radarAccessibilityValue)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityAction(named: Text(NSLocalizedString("solo.radar.replay.a11y", comment: ""))) {
                        guard !reduceMotion else { return }
                        replay()
                    }

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
                    let isStrongest = hasQualifyingStrongest && i == strongestIndex
                    let dotRadius = size * 0.018 * ((isWeakest || isStrongest) ? 1.3 : 1.0)
                    let dotPos = point(
                        center: center,
                        radius: radius * CGFloat(values[i] / 10.0) * CGFloat(drawProgress),
                        angle: angle
                    )
                    let dotColor: Color = isWeakest ? Self.amberAccent : (isStrongest ? Self.greenAccent : score.scoreColor)
                    Circle()
                        .fill(dotColor)
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
                    let isStrongest = hasQualifyingStrongest && i == strongestIndex
                    let labelDelay = Double(i) * 0.06
                    let labelOpacity = max(0, min(1, (drawProgress - labelDelay) / (1.0 - labelDelay)))
                    let iconColor: Color = isWeakest ? Self.amberAccent : (isStrongest ? Self.greenAccent : score.scoreColor)
                    let textColor: Color = isWeakest ? Self.amberAccent : (isStrongest ? Self.greenAccent : Color.primary)
                    let fontWeight: Font.Weight = (isWeakest || isStrongest) ? .bold : .semibold

                    VStack(spacing: 2) {
                        Image(systemName: axis.symbol)
                            .font(.system(size: size * 0.065))
                            .foregroundStyle(iconColor)
                        Text(String(animatedValue(values[i])))
                            .font(.system(size: size * 0.055, weight: fontWeight, design: .rounded))
                            .foregroundStyle(textColor)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .spring(response: Self.springDuration, dampingFraction: 0.75), value: animatedValue(values[i]))
                    }
                    .opacity(labelOpacity)
                    .position(pos)
                    .onTapGesture { tapAxis(i) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(Text(NSLocalizedString("solo.axis.tap.hint", comment: "")))
                    .accessibilityLabel(Text(axis.label))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityChartDescriptor(RadarChartDescriptor(
            values: Self.axes.map { ($0.label, score.breakdown[keyPath: $0.keyPath]) }
        ))
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

    /// Raw VoiceOver label string naming all six dimensions with their values,
    /// e.g. "Safety 9 of 10, Seating 8 of 10, ...". The overall score is exposed
    /// separately via `radarAccessibilityValueString`. Exposed for unit testing.
    var radarAccessibilityLabelString: String {
        let sortedDimensions = zip(Self.axes, values)
            .sorted { $0.1 > $1.1 }
        let dimensionParts = sortedDimensions.map { axis, val in
            "\(axis.label) \(Int(val)) of 10"
        }.joined(separator: ", ")

        var label = dimensionParts

        if hasQualifyingStrongest {
            let strongestName = Self.axes[strongestIndex].label
            let strongestSentence = String(
                format: NSLocalizedString("solo.radar.strongest.a11y", comment: ""),
                strongestName
            )
            label = "\(strongestSentence) \(label)"
        }

        if values[weakestIndex] < 6 {
            let weakestName = Self.axes[weakestIndex].label
            let weakestSentence = String(
                format: NSLocalizedString("solo.radar.weakest.a11y", comment: ""),
                weakestName
            )
            label += ". \(weakestSentence)"
        }

        return label
    }

    /// Raw VoiceOver value string announcing the overall Solo Score, e.g.
    /// "Solo Score 7.8 of 10". Exposed for unit testing.
    var radarAccessibilityValueString: String {
        let overallFormatted = String(format: "%.1f", score.overall)
        return String(format: NSLocalizedString("solo.a11y", comment: ""), overallFormatted)
    }

    /// VoiceOver label naming all six dimensions with their values.
    var radarAccessibilityLabel: Text { Text(radarAccessibilityLabelString) }

    /// VoiceOver value announcing the overall Solo Score.
    var radarAccessibilityValue: Text { Text(radarAccessibilityValueString) }

    // MARK: - Replay

    private func replay() {
        showReplayHint = false
        isReplaying = true
        drawProgress = 0
        withAnimation(.spring(response: Self.springDuration, dampingFraction: 0.75)) {
            drawProgress = 1
        }
        HapticService.shared.prepare(style: .soft)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.springDuration) {
            Haptics.impact(.soft)
            isReplaying = false
        }
    }

    // MARK: - Honest-tradeoff caption

    // Renders for both radar and fallback-bars paths via body's shared VStack.
    // Fixed-min-height container prevents layout jump during fade-in.
    @ViewBuilder private var weakestCaption: some View {
        let weakCaptionVisible = values[weakestIndex] < 6
        let strongCaptionVisible = hasQualifyingStrongest
        let anyVisible = weakCaptionVisible || strongCaptionVisible
        let fullyDrawn = drawProgress >= 0.99
        ZStack {
            VStack(spacing: 4) {
                if strongCaptionVisible {
                    let strongText = String(
                        format: NSLocalizedString("solo.radar.strongest", comment: ""),
                        Self.axes[strongestIndex].label
                    )
                    Button { if fullyDrawn { tapAxis(strongestIndex) } } label: {
                        Label(strongText, systemImage: "star.fill")
                            .font(.caption)
                            .foregroundStyle(Self.greenAccent)
                    }
                    .buttonStyle(.plain)
                    .opacity(fullyDrawn ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeIn(duration: 0.3), value: fullyDrawn)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text(Self.axes[strongestIndex].label))
                    .accessibilityHint(Text(NSLocalizedString("solo.axis.tap.hint", comment: "")))
                }
                if weakCaptionVisible {
                    let captionText = String(
                        format: NSLocalizedString("solo.radar.weakest", comment: ""),
                        Self.axes[weakestIndex].label
                    )
                    Button { if fullyDrawn { tapAxis(weakestIndex) } } label: {
                        Label(captionText, systemImage: "exclamationmark.bubble")
                            .font(.caption)
                            .foregroundStyle(Self.amberAccent)
                    }
                    .buttonStyle(.plain)
                    .opacity(fullyDrawn ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeIn(duration: 0.3), value: fullyDrawn)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text(Self.axes[weakestIndex].label))
                    .accessibilityHint(Text(NSLocalizedString("solo.axis.tap.hint", comment: "")))
                }
            }
        }
        .frame(minHeight: anyVisible ? 20 : 0)
    }

    // MARK: - Fallback bars

    private var fallbackBars: some View {
        VStack(spacing: 8) {
            // Summary accessibility element — VoiceOver lands here first
            Rectangle().fill(.clear).frame(height: 0)
                .accessibilityElement()
                .accessibilityLabel(radarAccessibilityLabel)
                .accessibilityValue(radarAccessibilityValue)
                .accessibilityAddTraits(.isImage)
                .accessibilityAction(named: Text(NSLocalizedString("solo.radar.replay.a11y", comment: ""))) {
                    guard !reduceMotion else { return }
                    replay()
                }

            ForEach(0..<Self.axes.count, id: \.self) { i in
                let axis = Self.axes[i]
                let val = values[i]
                let isWeakest = i == weakestIndex
                let isStrongest = hasQualifyingStrongest && i == strongestIndex
                let barDelay = Double(i) * 0.06
                let barProgress = max(0, min(1, (drawProgress - barDelay) / (1.0 - barDelay)))
                let iconColor: Color = isWeakest ? Self.amberAccent : (isStrongest ? Self.greenAccent : score.scoreColor)
                let textColor: Color = isWeakest ? Self.amberAccent : (isStrongest ? Self.greenAccent : Color.primary)
                HStack(spacing: 8) {
                    Image(systemName: axis.symbol)
                        .font(.caption)
                        .foregroundStyle(iconColor)
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
                    Text(String(animatedValue(val)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(textColor)
                        .fontWeight((isWeakest || isStrongest) ? .bold : .regular)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .spring(response: Self.springDuration, dampingFraction: 0.75), value: animatedValue(val))
                        .frame(width: 24, alignment: .trailing)
                        .accessibilityHidden(true)
                }
                .onTapGesture { tapAxis(i) }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text(NSLocalizedString("solo.axis.tap.hint", comment: "")))
                .accessibilityLabel(Text(axis.label))
            }
        }
    }
}

// MARK: - AXChartDescriptor

private struct RadarChartDescriptor: AXChartDescriptorRepresentable {
    let values: [(label: String, value: Double)]

    func makeChartDescriptor() -> AXChartDescriptor {
        let categoryAxis = AXCategoricalDataAxisDescriptor(
            title: NSLocalizedString("solo.radar.axis.dimension", comment: ""),
            categoryOrder: values.map(\.label)
        )
        let valueAxis = AXNumericDataAxisDescriptor(
            title: NSLocalizedString("solo.scoreTitle", comment: ""),
            range: 0...10,
            gridlinePositions: [0, 5, 10]
        ) { value in "\(Int(value))" }

        let dataPoints = values.map { pair in
            AXDataPoint(x: .category(pair.label), y: .number(pair.value))
        }
        let series = AXDataSeriesDescriptor(
            name: NSLocalizedString("solo.scoreTitle", comment: ""),
            isContinuous: false,
            dataPoints: dataPoints
        )
        return AXChartDescriptor(
            title: NSLocalizedString("solo.scoreTitle", comment: ""),
            summary: nil,
            xAxis: categoryAxis,
            yAxis: valueAxis,
            additionalAxes: [],
            series: [series]
        )
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {}
}

// MARK: - Axis tooltip

extension SoloScoreRadarChart {
    @MainActor
    private func tapAxis(_ index: Int) {
        tooltipDismissTask?.cancel()
        if selectedAxis == index {
            selectedAxis = nil
        } else {
            selectedAxis = index
            Haptics.selection()
            let task = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(Self.tooltipAutoDismissSeconds * 1_000_000_000))
                if !Task.isCancelled {
                    selectedAxis = nil
                }
            }
            tooltipDismissTask = task
        }
    }

    @ViewBuilder
    private func axisDimensionTooltip(for index: Int) -> some View {
        let axis = Self.axes[index]
        let val = Int(values[index].rounded())
        let desc = NSLocalizedString(axis.descKey, comment: "")
        GlassmorphismCapsule(
            horizontalPadding: 14,
            verticalPadding: 8,
            shadowRadius: 6,
            shadowY: 3
        ) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: axis.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(score.scoreColor)
                    Text(axis.label)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(val)/10")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(score.scoreColor)
                }
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(axis.label), \(val) of 10. \(desc)"))
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

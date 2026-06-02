import SwiftUI

/// "Solo 8.5" pill. Compact form for cards, expanded form for the detail sheet.
public struct SoloScoreBadge: View {
    let score: SoloScore
    var style: Style = .compact

    public enum Style { case compact, full }

    @State private var animatedScore: Double = 0
    @State private var appeared = false
    @State private var showBreakdown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(score: SoloScore, style: Style = .compact) {
        self.score = score
        self.style = style
    }

    public var body: some View {
        switch style {
        case .compact: compactView
        case .full: fullView
        }
    }

    private var isExcellent: Bool { score.overall >= 8.5 }

    private var compactView: some View {
        Button {
            showBreakdown.toggle()
            Haptics.impact(.light)
        } label: {
            HStack(spacing: 4) {
                if isExcellent {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.95))
                }
                Text(NSLocalizedString("solo.label", comment: "Solo"))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
                Text(formatted(animatedScore))
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: animatedScore))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(score.scoreColor.opacity(0.95))
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showBreakdown) {
            SoloScorePopoverContent(score: score)
        }
        .scaleEffect(appeared ? 1 : 0.7)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            appeared = true
            updateAnimatedScore()
        }
        .accessibilityLabel(Text(
            isExcellent
                ? String(format: NSLocalizedString("solo.a11y", comment: "Solo Score %@ of 10"), formatted(score.overall))
                    + ", " + NSLocalizedString("solo.excellent.a11y", comment: "Excellent for solo travelers")
                : String(format: NSLocalizedString("solo.a11y", comment: "Solo Score %@ of 10"), formatted(score.overall))
        ))
        .accessibilityHint(Text(NSLocalizedString("solo.compact.a11y.hint", comment: "Double tap to see score breakdown")))
        .accessibilityAddTraits(.isButton)
        .onChange(of: score.overall) { _, _ in
            appeared = true
            updateAnimatedScore()
        }
    }

    private var fullView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("solo.scoreTitle", comment: "Solo Score"))
                    .font(.headline)
                Spacer()
                Text(formatted(animatedScore))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(score.scoreColor)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: animatedScore))
                    .accessibilityLabel(Text(String(
                        format: NSLocalizedString("solo.a11y", comment: "Solo Score %@ of 10"),
                        formatted(score.overall)
                    )))
            }
            if let hint = score.hint {
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // Per-dimension breakdown intentionally omitted: the detail view
            // renders SoloScoreRadarChart directly below this badge, so a
            // second bar list would duplicate it. This badge is the score
            // header only (overall + hint).
        }
        .onAppear {
            if reduceMotion {
                animatedScore = score.overall
            } else {
                withAnimation(.easeOut(duration: 0.7)) {
                    animatedScore = score.overall
                }
            }
        }
        .onChange(of: score.overall) { triggerAnimation() }
    }

    private func updateAnimatedScore() {
        if reduceMotion {
            animatedScore = score.overall
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                animatedScore = score.overall
            }
        }
    }

    private func triggerAnimation() {
        if reduceMotion {
            animatedScore = score.overall
        } else {
            withAnimation(.easeOut(duration: 0.5)) {
                animatedScore = score.overall
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private struct SoloScorePopoverContent: View {
    let score: SoloScore
    @State private var appeared = false
    @State private var barsFilled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct DimensionRow {
        let labelKey: String
        let value: Double
    }

    private var dimensions: [DimensionRow] {
        [
            DimensionRow(labelKey: "solo.dim.seating",    value: score.breakdown.seatingFriendly),
            DimensionRow(labelKey: "solo.dim.ratio",      value: score.breakdown.soloPatronRatio),
            DimensionRow(labelKey: "solo.dim.pressure",   value: score.breakdown.staffPressure),
            DimensionRow(labelKey: "solo.dim.portioning", value: score.breakdown.soloPortioning),
            DimensionRow(labelKey: "solo.dim.ambiance",   value: score.breakdown.ambianceFit),
            DimensionRow(labelKey: "solo.dim.safety",     value: score.breakdown.safety),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("solo.breakdown.title", comment: "Solo Score breakdown"))
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1f", score.overall))
                    .font(.title3.bold())
                    .foregroundStyle(score.scoreColor)
                    .monospacedDigit()
            }

            if let hint = score.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(Array(dimensions.enumerated()), id: \.offset) { index, row in
                dimensionRow(label: NSLocalizedString(row.labelKey, comment: ""), value: row.value, index: index)
            }

            if score.basedOnCount > 0 {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: NSLocalizedString("solo.basedOn", comment: "Based on N solo travelers"), score.basedOnCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(String(format: NSLocalizedString("solo.basedOn", comment: "Based on N solo travelers"), score.basedOnCount)))
            }
        }
        .padding()
        .frame(minWidth: 240)
        .presentationCompactAdaptation(.popover)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            if reduceMotion {
                appeared = true
                barsFilled = true
            } else {
                withAnimation(.easeIn(duration: 0.2)) {
                    appeared = true
                }
                barsFilled = true
            }
        }
    }

    private func dimensionRow(label: String, value: Double, index: Int) -> some View {
        let clamped = max(0, min(10, value))
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f", value))
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(score.scoreColor.opacity(0.8))
                            .frame(width: barsFilled ? geo.size.width * CGFloat(clamped / 10) : 0)
                            .animation(
                                reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8)
                                    .delay(Double(index) * 0.05),
                                value: barsFilled
                            )
                    }
            }
            .frame(height: 4)
        }
    }
}

#Preview {
    let excellentScore = SoloScore(
        overall: 8.7,
        breakdown: .init(seatingFriendly: 9, soloPatronRatio: 8, staffPressure: 9, soloPortioning: 10, ambianceFit: 8, safety: 9),
        hint: "Order at the bar, sit upstairs.",
        basedOnCount: 14
    )
    let midScore = SoloScore(
        overall: 5.2,
        breakdown: .init(seatingFriendly: 5, soloPatronRatio: 5, staffPressure: 6, soloPortioning: 5, ambianceFit: 5, safety: 5),
        hint: nil,
        basedOnCount: 3
    )
    VStack(spacing: 24) {
        SoloScoreBadge(score: excellentScore, style: .compact)
        SoloScoreBadge(score: midScore, style: .compact)
        SoloScoreBadge(score: excellentScore, style: .full)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    .padding()
}

#Preview("Compact count-up") {
    struct CompactCountUpPreview: View {
        @State private var score = SoloScore(
            overall: 5.0,
            breakdown: .init(seatingFriendly: 5, soloPatronRatio: 5, staffPressure: 5, soloPortioning: 5, ambianceFit: 5, safety: 5),
            basedOnCount: 4
        )

        var body: some View {
            VStack(spacing: 20) {
                SoloScoreBadge(score: score, style: .compact)
                Button(NSLocalizedString("preview.raiseScore", comment: "Raise Score")) {
                    score = SoloScore(
                        overall: 9.2,
                        breakdown: .init(seatingFriendly: 9, soloPatronRatio: 9, staffPressure: 9, soloPortioning: 9, ambianceFit: 10, safety: 9),
                        basedOnCount: 20
                    )
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
    return CompactCountUpPreview()
}

#Preview("Score Breakdown Popover") {
    let score = SoloScore(
        overall: 7.8,
        breakdown: .init(seatingFriendly: 8, soloPatronRatio: 7, staffPressure: 9, soloPortioning: 6, ambianceFit: 8, safety: 9),
        hint: "Corner seats by the window are ideal.",
        basedOnCount: 11
    )
    SoloScorePopoverContent(score: score)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
}

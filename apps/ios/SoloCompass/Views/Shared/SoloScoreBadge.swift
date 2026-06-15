import SwiftUI

/// "Solo 8.5" pill. Compact form for cards, expanded form for the detail sheet.
public struct SoloScoreBadge: View {
    let score: SoloScore
    var style: Style = .compact

    public enum Style { case compact, full }

    @State private var animatedScore: Double = 0
    @State private var appeared = false
    @State private var showBreakdown = false
    @State private var twinkle = false
    @State private var cautionPulse = false
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
    private var isCaution: Bool { score.overall < 4.0 }

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
                        .symbolEffect(.variableColor.iterative, isActive: twinkle && !reduceMotion)
                        .scaleEffect(twinkle && !reduceMotion ? 1.12 : 1.0)
                        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: twinkle)
                        .accessibilityHidden(true)
                } else if isCaution {
                    Image(systemName: "person.fill.questionmark")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.95))
                        .scaleEffect(cautionPulse && !reduceMotion ? 1.12 : 1.0)
                        .opacity(cautionPulse && !reduceMotion ? 1.0 : 0.78)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: cautionPulse)
                        .accessibilityHidden(true)
                }
                Text(NSLocalizedString("solo.label", comment: "Solo"))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(formatted(animatedScore))
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: animatedScore))
                    Text("/10")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
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
            if isExcellent && !reduceMotion {
                twinkle = true
            }
            if isCaution && !reduceMotion {
                cautionPulse = true
            }
        }
        .accessibilityLabel(Text(
            isExcellent
                ? String(format: NSLocalizedString("solo.a11y", comment: "Solo Score %@ of 10"), formatted(score.overall))
                    + ", " + NSLocalizedString("solo.excellent.a11y", comment: "Excellent for solo travelers")
                : isCaution
                    ? String(format: NSLocalizedString("solo.a11y", comment: "Solo Score %@ of 10"), formatted(score.overall))
                        + ", " + NSLocalizedString("solo.caution.a11y", comment: "may feel exposed for solo travelers")
                    : String(format: NSLocalizedString("solo.a11y", comment: "Solo Score %@ of 10"), formatted(score.overall))
        ))
        .accessibilityHint(Text(NSLocalizedString("solo.compact.a11y.hint", comment: "Double tap to see score breakdown")))
        .accessibilityAddTraits(.isButton)
        .onChange(of: score.overall) { _, newValue in
            appeared = true
            updateAnimatedScore()
            let nowExcellent = newValue >= 8.5
            if nowExcellent && !reduceMotion {
                twinkle = false
                twinkle = true
            } else if !nowExcellent {
                twinkle = false
            }
            let nowCaution = newValue < 4.0
            if nowCaution && !reduceMotion {
                cautionPulse = false
                cautionPulse = true
            } else if !nowCaution {
                cautionPulse = false
            }
        }
    }

    private var fullView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("solo.scoreTitle", comment: "Solo Score"))
                    .font(.headline)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(formatted(animatedScore))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(score.scoreColor)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: animatedScore))
                    Text("/10")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
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
    @State private var expandedIndex: Int? = nil
    @State private var animatedOverall: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let weakestThreshold: Double = 5.0
    private let safetyCautionThreshold: Double = 4.0

    private var isEarlyEstimate: Bool { score.basedOnCount > 0 && score.basedOnCount <= 3 }

    private struct DimensionRow {
        let labelKey: String
        let descKey: String
        let value: Double
    }

    private var dimensions: [DimensionRow] {
        [
            DimensionRow(labelKey: "solo.dim.seating",    descKey: "solo.seating.desc",   value: score.breakdown.seatingFriendly),
            DimensionRow(labelKey: "solo.dim.ratio",      descKey: "solo.patrons.desc",   value: score.breakdown.soloPatronRatio),
            DimensionRow(labelKey: "solo.dim.pressure",   descKey: "solo.staff.desc",     value: score.breakdown.staffPressure),
            DimensionRow(labelKey: "solo.dim.portioning", descKey: "solo.portioning.desc", value: score.breakdown.soloPortioning),
            DimensionRow(labelKey: "solo.dim.ambiance",   descKey: "solo.ambiance.desc",  value: score.breakdown.ambianceFit),
            DimensionRow(labelKey: "solo.dim.safety",     descKey: "solo.safety.desc",    value: score.breakdown.safety),
        ]
    }

    private let strongestThreshold: Double = 7.5

    private var safetyIndex: Int {
        dimensions.firstIndex(where: { $0.labelKey == "solo.dim.safety" }) ?? (dimensions.count - 1)
    }

    private var showSafetyCaution: Bool {
        score.breakdown.safety < safetyCautionThreshold
    }

    private var weakestIndex: Int {
        dimensions.enumerated().min(by: { $0.element.value < $1.element.value })?.offset ?? 0
    }

    private var weakestLabel: String {
        NSLocalizedString(dimensions[weakestIndex].labelKey, comment: "")
    }

    private var showWeakestCaption: Bool {
        dimensions[weakestIndex].value < weakestThreshold
            && !(weakestIndex == safetyIndex && showSafetyCaution)
    }

    private var strongestIndex: Int {
        dimensions.enumerated().max(by: { $0.element.value < $1.element.value })?.offset ?? 0
    }

    private var strongestLabel: String {
        NSLocalizedString(dimensions[strongestIndex].labelKey, comment: "")
    }

    private var showStrongestCaption: Bool {
        dimensions[strongestIndex].value >= strongestThreshold && strongestIndex != weakestIndex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("solo.breakdown.title", comment: "Solo Score breakdown"))
                    .font(.headline)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(String(format: "%.1f", animatedOverall))
                        .font(.title3.bold())
                        .foregroundStyle(score.scoreColor)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: animatedOverall))
                    Text("/10")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let hint = score.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showStrongestCaption {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text(String(format: NSLocalizedString("solo.strongest", comment: ""), strongestLabel))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(String(format: NSLocalizedString("solo.strongest.a11y", comment: ""), strongestLabel)))
            }

            if showWeakestCaption {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(String(format: NSLocalizedString("solo.weakest", comment: ""), weakestLabel))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(String(format: NSLocalizedString("solo.weakest.a11y", comment: ""), weakestLabel)))
            }

            if showSafetyCaution {
                HStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled.slash")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.85, green: 0.38, blue: 0.1))
                        .accessibilityHidden(true)
                    Text(NSLocalizedString("solo.safety.caution", comment: ""))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color(red: 0.65, green: 0.3, blue: 0.05))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.14), in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(NSLocalizedString("solo.safety.caution.a11y", comment: "")))
                .scaleEffect(appeared && !reduceMotion ? 1 : (reduceMotion ? 1 : 0.92))
                .opacity(appeared ? 1 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: appeared)
            }

            Divider()

            ForEach(Array(dimensions.enumerated()), id: \.offset) { index, row in
                dimensionRow(
                    label: NSLocalizedString(row.labelKey, comment: ""),
                    desc: NSLocalizedString(row.descKey, comment: ""),
                    value: row.value,
                    index: index,
                    isWeakest: index == weakestIndex && showWeakestCaption,
                    isStrongest: index == strongestIndex && showStrongestCaption && index != weakestIndex
                )
            }

            if score.basedOnCount > 0 {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(isEarlyEstimate ? Color.orange.opacity(0.9) : .secondary)
                    Text(String(format: NSLocalizedString("solo.basedOn", comment: "Based on N solo travelers"), score.basedOnCount))
                        .font(.caption)
                        .foregroundStyle(isEarlyEstimate ? Color.orange.opacity(0.9) : .secondary)
                    if isEarlyEstimate {
                        HStack(spacing: 3) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 9, weight: .medium))
                                .accessibilityHidden(true)
                            Text(NSLocalizedString("solo.earlyEstimate", comment: "Early estimate"))
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(Color.orange.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                        .scaleEffect(appeared && !reduceMotion ? 1 : (reduceMotion ? 1 : 0.85))
                        .opacity(appeared ? 1 : 0)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(
                    isEarlyEstimate
                        ? String(format: NSLocalizedString("solo.basedOn", comment: "Based on N solo travelers"), score.basedOnCount)
                            + ", " + NSLocalizedString("solo.earlyEstimate.a11y", comment: "Early estimate, based on few solo travelers — score may shift")
                        : String(format: NSLocalizedString("solo.basedOn", comment: "Based on N solo travelers"), score.basedOnCount)
                ))
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
                animatedOverall = score.overall
            } else {
                withAnimation(.easeIn(duration: 0.2)) {
                    appeared = true
                }
                barsFilled = true
                withAnimation(.easeOut(duration: 0.6)) {
                    animatedOverall = score.overall
                }
            }
        }
        .onDisappear {
            appeared = false
            barsFilled = false
            expandedIndex = nil
        }
    }

    private func dimensionRow(label: String, desc: String, value: Double, index: Int, isWeakest: Bool, isStrongest: Bool = false) -> some View {
        let clamped = max(0, min(10, value))
        let barColor: Color = isWeakest ? .orange.opacity(0.8) : isStrongest ? .green.opacity(0.8) : score.scoreColor.opacity(0.8)
        let isExpanded = expandedIndex == index
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                expandedIndex = isExpanded ? nil : index
            }
            Haptics.selection()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    if isWeakest {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                    } else if isStrongest {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                    }
                    Text(label)
                        .font(isWeakest || isStrongest ? .caption.bold() : .caption)
                        .foregroundStyle(isWeakest || isStrongest ? .primary : .secondary)
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(String(format: "%.1f", value))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                        Text("/10")
                            .font(.system(size: 8, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(barColor)
                                .frame(width: barsFilled ? geo.size.width * CGFloat(clamped / 10) : 0)
                                .animation(
                                    reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8)
                                        .delay(Double(index) * 0.05),
                                    value: barsFilled
                                )
                        }
                }
                .frame(height: 4)
                if isExpanded {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.95).combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(isExpanded ? "\(String(format: "%.1f", value)), \(desc)" : String(format: "%.1f", value)))
        .accessibilityHint(Text(NSLocalizedString("solo.axis.tap.hint", comment: "")))
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
    let cautionScore = SoloScore(
        overall: 3.1,
        breakdown: .init(seatingFriendly: 2, soloPatronRatio: 3, staffPressure: 4, soloPortioning: 3, ambianceFit: 3, safety: 4),
        hint: "Can feel exposed as a solo diner.",
        basedOnCount: 7
    )
    VStack(spacing: 24) {
        SoloScoreBadge(score: excellentScore, style: .compact)
        SoloScoreBadge(score: midScore, style: .compact)
        SoloScoreBadge(score: cautionScore, style: .compact)
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
    let cautionScore = SoloScore(
        overall: 3.1,
        breakdown: .init(seatingFriendly: 2, soloPatronRatio: 3, staffPressure: 4, soloPortioning: 3, ambianceFit: 3, safety: 3.5),
        hint: "Can feel exposed as a solo diner.",
        basedOnCount: 7
    )
    VStack(spacing: 24) {
        SoloScorePopoverContent(score: score)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        SoloScorePopoverContent(score: cautionScore)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    .padding()
}

#Preview("Early Estimate (basedOnCount: 2)") {
    let earlyScore = SoloScore(
        overall: 6.4,
        breakdown: .init(seatingFriendly: 7, soloPatronRatio: 6, staffPressure: 7, soloPortioning: 6, ambianceFit: 6, safety: 7),
        hint: "Score based on very few reports — may shift.",
        basedOnCount: 2
    )
    SoloScorePopoverContent(score: earlyScore)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
}

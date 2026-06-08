import SwiftUI

/// Small dot + level indicator. Drives the trust signal across the app.
public struct ConfidenceBadge: View {
    let confidence: Confidence
    var compact: Bool = true

    @State private var showSignals = false
    @State private var isPulsing = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(confidence: Confidence, compact: Bool = true) {
        self.confidence = confidence
        self.compact = compact
    }

    private var shouldPulse: Bool {
        compact && confidence.health != .healthy && !reduceMotion
    }

    public var body: some View {
        Button {
            Haptics.selection()
            if !reduceMotion {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { pressed = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { pressed = false }
                }
            }
            showSignals.toggle()
        } label: {
            HStack(spacing: 4) {
                ZStack {
                    if shouldPulse {
                        Circle()
                            .stroke(confidence.health.color, lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isPulsing ? 1.8 : 1.0)
                            .opacity(isPulsing ? 0.0 : 0.6)
                            .accessibilityHidden(true)
                    }
                    Circle()
                        .fill(confidence.health.color)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    if let symbol = confidence.health.accessibilitySymbol {
                        Image(systemName: symbol)
                            .font(.system(size: 4, weight: .bold))
                            .foregroundColor(.white)
                            .accessibilityHidden(true)
                    }
                }
                if !compact {
                    // Show the human-readable health label (Verified / Fading /
                    // …) instead of the opaque internal "L2" level code, which
                    // means nothing to a traveler.
                    Text("\(confidence.health.localizedDescription) · \(confidence.signals.totalCount) \(NSLocalizedString("confidence.signals", comment: "signals"))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .frame(minWidth: 44, minHeight: 32, alignment: .leading)
            .scaleEffect(pressed ? 0.86 : 1.0)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showSignals) {
            PopoverContent(confidence: confidence)
        }
        .accessibilityLabel(Text(String(format: NSLocalizedString("confidence.a11y.label", comment: ""), confidence.health.localizedDescription, confidence.level, confidence.signals.totalCount)))
        .accessibilityValue(Text(confidenceRelativeVerifiedString(confidence) ?? ""))
        .accessibilityHint(Text(NSLocalizedString("confidence.a11y.hint", comment: "")))
        .accessibilityAddTraits(.isButton)
        .onAppear {
            guard shouldPulse else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                withAnimation(.default) { isPulsing = false }
            } else if compact && confidence.health != .healthy {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
        }
    }
}

private struct PopoverContent: View {
    let confidence: Confidence
    @State private var appeared = false
    @State private var barsFilled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Normalized 0...1 strength per signal
    private var aiScrapeStrength: Double {
        max(0, 1 - Double(confidence.signals.aiScrapeAgeDays) / 90)
    }
    private var gpsStrength: Double {
        min(1, Double(confidence.signals.passiveGpsHits30d) / 30)
    }
    private var reportsStrength: Double {
        min(1, Double(confidence.signals.activeReports30d) / 10)
    }
    private var verificationsStrength: Double {
        min(1, Double(confidence.signals.trustedVerifications) / 3)
    }

    private struct SignalDescriptor {
        let symbol: String
        let label: String
        let value: String
        let strength: Double
        let index: Int
    }

    private var signalDescriptors: [SignalDescriptor] {
        [
            SignalDescriptor(symbol: "sparkles",
                             label: NSLocalizedString("confidence.aiScrape", comment: ""),
                             value: "\(confidence.signals.aiScrapeAgeDays)d",
                             strength: aiScrapeStrength,
                             index: 0),
            SignalDescriptor(symbol: "location.fill",
                             label: NSLocalizedString("confidence.gps", comment: ""),
                             value: "\(confidence.signals.passiveGpsHits30d)",
                             strength: gpsStrength,
                             index: 1),
            SignalDescriptor(symbol: "flag.fill",
                             label: NSLocalizedString("confidence.reports", comment: ""),
                             value: "\(confidence.signals.activeReports30d)",
                             strength: reportsStrength,
                             index: 2),
            SignalDescriptor(symbol: "checkmark.seal.fill",
                             label: NSLocalizedString("confidence.trusted", comment: ""),
                             value: "\(confidence.signals.trustedVerifications)",
                             strength: verificationsStrength,
                             index: 3)
        ]
    }

    private var strongestIndex: Int {
        signalDescriptors.max(by: { $0.strength < $1.strength })?.index ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: dot + health description + level capsule
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(confidence.health.color)
                        .frame(width: 10, height: 10)
                    if let symbol = confidence.health.accessibilitySymbol {
                        Image(systemName: symbol)
                            .font(.system(size: 5, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                Text(confidence.health.localizedDescription)
                    .font(.headline)
                Spacer()
                Text("L\(confidence.level)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(confidence.health.color.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Reason subhead
            Text(confidence.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Last verified line
            if let relativeDate = relativeVerifiedString {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(relativeDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Strongest signal caption
            let strongest = signalDescriptors[strongestIndex]
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(confidence.health.color)
                Text(String(format: NSLocalizedString("confidence.strongest", comment: ""), strongest.label))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Signal rows
            GeometryReader { geo in
                VStack(spacing: 8) {
                    ForEach(signalDescriptors, id: \.index) { descriptor in
                        signalRow(
                            symbol: descriptor.symbol,
                            label: descriptor.label,
                            value: descriptor.value,
                            strength: descriptor.strength,
                            isStrongest: descriptor.index == strongestIndex,
                            barWidth: geo.size.width,
                            rowIndex: descriptor.index
                        )
                    }
                }
            }
            .frame(height: CGFloat(signalDescriptors.count) * 44)
            .font(.caption)
        }
        .padding()
        .frame(minWidth: 240)
        .presentationCompactAdaptation(.popover)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeIn(duration: 0.2)) {
                appeared = true
            }
            if reduceMotion {
                barsFilled = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    barsFilled = true
                }
            }
        }
    }

    private var relativeVerifiedString: String? {
        confidenceRelativeVerifiedString(confidence)
    }

    private func a11yStrengthLabel(_ strength: Double) -> String {
        if strength >= 0.6 {
            return NSLocalizedString("confidence.strength.strong", comment: "")
        } else if strength >= 0.25 {
            return NSLocalizedString("confidence.strength.medium", comment: "")
        } else {
            return NSLocalizedString("confidence.strength.weak", comment: "")
        }
    }

    private func signalRow(
        symbol: String,
        label: String,
        value: String,
        strength: Double,
        isStrongest: Bool,
        barWidth: CGFloat,
        rowIndex: Int
    ) -> some View {
        let fillWidth = barsFilled ? barWidth * strength : 0
        let springDelay = reduceMotion ? 0.0 : Double(rowIndex) * 0.07
        let animation = reduceMotion
            ? Animation.linear(duration: 0)
            : Animation.spring(response: 0.45, dampingFraction: 0.72).delay(springDelay)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                if isStrongest {
                    Text(label)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                } else {
                    Text(label).foregroundStyle(.secondary)
                }
                Spacer()
                Text(value).fontWeight(.medium)
            }
            // Strength bar
            let barHeight: CGFloat = isStrongest ? 5 : 3
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: barHeight)
                Capsule()
                    .fill(confidence.health.color.opacity(isStrongest ? 1.0 : 0.7))
                    .frame(width: fillWidth, height: barHeight)
                    .shadow(color: isStrongest ? confidence.health.color.opacity(0.5) : .clear, radius: 3)
                    .animation(animation, value: barsFilled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("\(value), \(a11yStrengthLabel(strength))"))
    }
}

fileprivate func confidenceRelativeVerifiedString(_ confidence: Confidence) -> String? {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    let relative = formatter.localizedString(for: confidence.lastVerifiedAt, relativeTo: Date())
    let format = NSLocalizedString("confidence.lastVerified", comment: "")
    return String(format: format, relative)
}

#Preview {
    VStack(spacing: 16) {
        ConfidenceBadge(
            confidence: Confidence(
                level: 4,
                lastVerifiedAt: Date(),
                reason: "Verified by trusted reporter",
                signals: .init(aiScrapeAgeDays: 7, passiveGpsHits30d: 24, activeReports30d: 8, trustedVerifications: 1)
            ),
            compact: false
        )
        ConfidenceBadge(
            confidence: Confidence(
                level: 1,
                lastVerifiedAt: Date().addingTimeInterval(-90 * 86_400),
                reason: "No recent reports",
                signals: .init(aiScrapeAgeDays: 90, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
            ),
            compact: false
        )
        // Compact dot with pulsing halo — questioned state
        ConfidenceBadge(
            confidence: Confidence(
                level: 1,
                lastVerifiedAt: Date().addingTimeInterval(-20 * 86_400),
                reason: "Community reports conflict",
                signals: .init(aiScrapeAgeDays: 20, passiveGpsHits30d: 2, activeReports30d: 3, trustedVerifications: 0)
            ),
            compact: true
        )
        // GPS dominant — strongest bar emphasis visible
        ConfidenceBadge(
            confidence: Confidence(
                level: 3,
                lastVerifiedAt: Date().addingTimeInterval(-5 * 86_400),
                reason: "High passive GPS activity",
                signals: .init(aiScrapeAgeDays: 60, passiveGpsHits30d: 28, activeReports30d: 1, trustedVerifications: 0)
            ),
            compact: false
        )
    }
    .padding()
}

import SwiftUI

/// Small dot + level indicator. Drives the trust signal across the app.
public struct ConfidenceBadge: View {
    let confidence: Confidence
    var compact: Bool = true

    @State private var showSignals = false
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(confidence: Confidence, compact: Bool = true) {
        self.confidence = confidence
        self.compact = compact
    }

    private var shouldPulse: Bool {
        compact && confidence.health != .healthy && !reduceMotion
    }

    public var body: some View {
        Button { showSignals.toggle() } label: {
            HStack(spacing: 4) {
                ZStack {
                    if shouldPulse {
                        Circle()
                            .stroke(confidence.health.color, lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isPulsing ? 1.8 : 1.0)
                            .opacity(isPulsing ? 0.0 : 0.6)
                    }
                    Circle()
                        .fill(confidence.health.color)
                        .frame(width: 8, height: 8)
                    if let symbol = confidence.health.accessibilitySymbol {
                        Image(systemName: symbol)
                            .font(.system(size: 4, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                if !compact {
                    Text("L\(confidence.level) · \(confidence.signals.totalCount) \(NSLocalizedString("confidence.signals", comment: "signals"))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .frame(minWidth: 44, minHeight: 32, alignment: .leading)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showSignals) {
            PopoverContent(confidence: confidence)
        }
        .accessibilityLabel(Text(confidence.health.localizedDescription))
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

            Divider()

            // Signal rows
            Group {
                signalRow(
                    symbol: "sparkles",
                    label: NSLocalizedString("confidence.aiScrape", comment: ""),
                    value: "\(confidence.signals.aiScrapeAgeDays)d"
                )
                signalRow(
                    symbol: "location.fill",
                    label: NSLocalizedString("confidence.gps", comment: ""),
                    value: "\(confidence.signals.passiveGpsHits30d)"
                )
                signalRow(
                    symbol: "flag.fill",
                    label: NSLocalizedString("confidence.reports", comment: ""),
                    value: "\(confidence.signals.activeReports30d)"
                )
                signalRow(
                    symbol: "checkmark.seal.fill",
                    label: NSLocalizedString("confidence.trusted", comment: ""),
                    value: "\(confidence.signals.trustedVerifications)"
                )
            }
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
        }
    }

    private var relativeVerifiedString: String? {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: confidence.lastVerifiedAt, relativeTo: Date())
        let format = NSLocalizedString("confidence.lastVerified", comment: "")
        return String(format: format, relative)
    }

    private func signalRow(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }
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
    }
    .padding()
}

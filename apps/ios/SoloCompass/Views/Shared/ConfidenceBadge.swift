import SwiftUI

/// Small dot + level indicator. Drives the trust signal across the app.
public struct ConfidenceBadge: View {
    let confidence: Confidence
    var compact: Bool = true

    @State private var showSignals = false

    public init(confidence: Confidence, compact: Bool = true) {
        self.confidence = confidence
        self.compact = compact
    }

    public var body: some View {
        Button { showSignals.toggle() } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(confidence.health.color)
                    .frame(width: 8, height: 8)
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
            VStack(alignment: .leading, spacing: 8) {
                Text(confidence.health.localizedDescription)
                    .font(.headline)
                Text(confidence.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Divider()
                Group {
                    signalLine(label: NSLocalizedString("confidence.aiScrape", comment: ""), value: "\(confidence.signals.aiScrapeAgeDays)d")
                    signalLine(label: NSLocalizedString("confidence.gps", comment: ""), value: "\(confidence.signals.passiveGpsHits30d)")
                    signalLine(label: NSLocalizedString("confidence.reports", comment: ""), value: "\(confidence.signals.activeReports30d)")
                    signalLine(label: NSLocalizedString("confidence.trusted", comment: ""), value: "\(confidence.signals.trustedVerifications)")
                }
                .font(.caption)
            }
            .padding()
            .frame(minWidth: 240)
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(Text(confidence.health.localizedDescription))
    }

    private func signalLine(label: String, value: String) -> some View {
        HStack {
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
    }
    .padding()
}

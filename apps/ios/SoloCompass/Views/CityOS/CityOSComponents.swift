import SwiftUI

// MARK: - City OS v2 · shared render primitives (PRD §5.2–5.3)
//
// The kit sheet, live sheet, and chat event card all need the same two honest
// signals — a health dot (never color-only) and a relative "last verified"
// caption — so they live here once. Both are pure presentational leaves.

/// A confidence/freshness dot for a City-OS row. Renders `HealthStatus.color`
/// with the shape-coded `accessibilitySymbol` overlaid, so colorblind users can
/// tell states apart by glyph, never by hue alone (the "可信 = 健康度点" axiom).
struct HealthDot: View {
    let status: HealthStatus
    var size: CGFloat = 9

    var body: some View {
        ZStack {
            Circle()
                .fill(status.color)
                .frame(width: size, height: size)
            if let symbol = status.accessibilitySymbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.6, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A monospaced "last verified N days ago" caption. `RelativeDateTimeFormatter`
/// keeps it locale-correct (中文 "3天前" / English "3 days ago"). Shows a
/// dedicated "unverifiable" string when the timestamp is missing — matching the
/// `.questioned` health `CityBriefHealth` assigns to an un-verified row.
struct RelativeTimeText: View {
    let date: Date?
    var now: Date = Date()

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private var label: String {
        guard let date else {
            return NSLocalizedString("cityos.health.unverified", comment: "Freshness unknown")
        }
        return Self.formatter.localizedString(for: date, relativeTo: now)
    }

    var body: some View {
        Text(label)
            .ctMono(10.5)
            .foregroundStyle(CT.fgSubtle)
    }
}

/// Combines a `HealthDot` and its relative-time caption into the standard
/// City-OS freshness footer (dot + "3天前"), with a combined VoiceOver label so
/// the two read as one honest statement rather than two loose fragments.
struct FreshnessFooter: View {
    let status: HealthStatus
    let lastVerifiedAt: Date?
    var now: Date = Date()

    var body: some View {
        HStack(spacing: 5) {
            HealthDot(status: status)
            RelativeTimeText(date: lastVerifiedAt, now: now)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(a11y))
    }

    private var a11y: String {
        let freshness = lastVerifiedAt.map {
            RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: now)
        } ?? NSLocalizedString("cityos.health.unverified", comment: "Freshness unknown")
        return "\(status.localizedDescription), \(freshness)"
    }
}

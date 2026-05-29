import SwiftUI

/// Transparency pill (US-004). Rendered on an experience card when its content
/// came from a degraded skeleton fallback (`AISynthesisQuality.skeleton`) rather
/// than a real AI synthesis. The muted styling — `CT.fgMuted`, never the accent —
/// keeps it low-key so users read it as "this is placeholder data", not as a
/// promoted feature.
public struct SkeletonBadgeView: View {
    public init() {}

    public var body: some View {
        Text(Self.label)
            .font(CT.body(10, .medium))
            .foregroundStyle(CT.fgMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(CT.fgMuted.opacity(0.12)))
            .accessibilityElement()
            .accessibilityLabel(Self.accessibilityLabel)
    }

    /// Localized pill text — "Limited data" / "数据有限".
    static var label: String {
        NSLocalizedString("ai.skeleton.pill", comment: "Pill shown when a card uses skeleton placeholder data")
    }

    /// VoiceOver reads the label plus a hint that this is placeholder content.
    static var accessibilityLabel: String {
        label + ", " + NSLocalizedString(
            "ai.skeleton.pill.a11y",
            comment: "Accessibility hint clarifying the badge marks placeholder content" // anti-pattern-lint:allow transparency indicator for AI synthesis quality, not gamification
        )
    }
}

#Preview("Skeleton badge") { // anti-pattern-lint:allow transparency indicator for AI synthesis quality, not gamification
    VStack(spacing: 16) {
        SkeletonBadgeView()
        HStack {
            Text("Quiet corner café")
                .font(.headline)
            SkeletonBadgeView()
        }
    }
    .padding()
    .background(CT.bgWarm)
}

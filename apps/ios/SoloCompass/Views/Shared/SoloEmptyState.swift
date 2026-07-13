import SwiftUI

// MARK: - SoloEmptyState (audit emptystate-01)
//
// One warm-amber empty-state container for the whole app. Before this, empty
// states split into two worlds: 8 files used the system `ContentUnavailableView`
// (cold gray secondary text) and 20+ hand-rolled Image+Text+Button stacks with
// inconsistent icon sizes, spacing, and colors. Both read as "a stranger's
// stock iOS screen" rather than Solo's warm identity.
//
// This gives every empty state the same amber icon tile, editorial title, and
// muted subtitle — with an optional CTA — so the moment a user hits an empty
// list still feels like the same app. Adopt it in place of both the hand-rolled
// stacks and (where brand warmth matters) ContentUnavailableView.

public struct SoloEmptyState: View {
    let systemImage: String
    let title: String
    let message: String?
    let actionTitle: String?
    let action: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        systemImage: String,
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Space.lg) {
            // Amber icon tile — a warm 64pt rounded square with the glyph at
            // ~28pt, replacing the cold system secondary tint.
            ZStack {
                Radius.shape(Radius.lg)
                    .fill(CT.accentSoft)
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(CT.accent)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)

            VStack(spacing: Space.sm) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(CT.textPrimaryAdaptive)
                    .multilineTextAlignment(.center)

                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(CT.textMutedAdaptive)
                        .multilineTextAlignment(.center)
                }
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CT.accent)
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.sm)
                        .background(CT.accentSoft, in: Capsule())
                }
                .padding(.top, Space.xs)
            }
        }
        .padding(Space.xxxl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview("With CTA") {
    SoloEmptyState(
        systemImage: "figure.walk",
        title: "No saved places yet",
        message: "The places you save will gather here for your next wander.",
        actionTitle: "Explore the map",
        action: {}
    )
    .background(CT.bgWarm)
}

#Preview("Message only") {
    SoloEmptyState(
        systemImage: "paperplane",
        title: "No requests right now",
        message: "When someone asks to join your route, it'll show up here."
    )
    .background(CT.bgWarm)
}

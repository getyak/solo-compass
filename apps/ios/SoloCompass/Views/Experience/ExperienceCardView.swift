import SwiftUI

/// Floating card that slides up when a marker is tapped. Tap → expand. Swipe
/// down → dismiss. Swipe up → full detail sheet.
public struct ExperienceCardView: View {
    let experience: Experience
    var onExpand: () -> Void
    var onDismiss: () -> Void

    @GestureState private var dragTranslation: CGFloat = 0
    @State private var dragOffset: CGFloat = 0

    // Pre-allocated so prepare() can be called when the drag starts.
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    public init(
        experience: Experience,
        onExpand: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.experience = experience
        self.onExpand = onExpand
        self.onDismiss = onDismiss
    }

    /// Rubber-bands upward drags to 40% travel; downward dismissal drags follow 1:1.
    private func rubberBanded(_ t: CGFloat) -> CGFloat {
        t < 0 ? t * 0.4 : t
    }

    private var totalOffset: CGFloat {
        rubberBanded(dragTranslation) + dragOffset
    }

    /// Fades in both directions: downward (dismiss) and upward (expand).
    private var dragOpacity: Double {
        1 - min(0.4, abs(dragTranslation) / 300)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: experience.category.symbol)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(experience.category.color))

                VStack(alignment: .leading, spacing: 2) {
                    Text(experience.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(experience.location.placeNameRomanized ?? experience.location.addressHint ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                ConfidenceBadge(confidence: experience.confidence, compact: true)
            }

            Text(experience.oneLiner)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)

            HStack {
                SoloScoreBadge(score: experience.soloScore, style: .compact)
                if experience.isBestNow() {
                    Label(NSLocalizedString("experience.bestNow", comment: ""), systemImage: "sparkle")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255).opacity(0.2))
                        )
                        .foregroundStyle(Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255))
                }
                Spacer()
                Button(action: onExpand) {
                    Text(NSLocalizedString("experience.viewDetails", comment: "View details"))
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 12, y: -2)
        )
        .padding(.horizontal, 12)
        .offset(y: totalOffset)
        .opacity(dragOpacity)
        .gesture(
            DragGesture(minimumDistance: 20)
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation.height
                }
                .onChanged { _ in
                    feedbackGenerator.prepare()
                }
                .onEnded { value in
                    let t = value.translation.height
                    // Commit the live visual position into dragOffset before
                    // @GestureState resets dragTranslation to 0, so the card
                    // stays at its dragged position rather than snapping back
                    // before the exit transition runs.
                    dragOffset = rubberBanded(t)
                    if t > 60 {
                        feedbackGenerator.impactOccurred()
                        onDismiss()
                    } else if t < -60 {
                        feedbackGenerator.impactOccurred()
                        onExpand()
                    } else {
                        withAnimation(.interactiveSpring()) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onTapGesture { onExpand() }
        .onAppear {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            "\(experience.title). \(experience.oneLiner). " +
            String(format: NSLocalizedString("solo.a11y", comment: "Solo Score %@ of 10"),
                   String(format: "%.1f", experience.soloScore.overall))
        ))
        .accessibilityHint(Text(NSLocalizedString("experience.card.hint", comment: "Double tap to view details")))
    }
}

#Preview {
    if let exp = ExperienceService.hardcodedSeed.first {
        VStack {
            Spacer()
            ExperienceCardView(
                experience: exp,
                onExpand: {},
                onDismiss: {}
            )
        }
        .background(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255))
    } else {
        Text("No seed data")
    }
}

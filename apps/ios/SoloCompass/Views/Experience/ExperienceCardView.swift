import SwiftUI

/// Floating card that slides up when a marker is tapped. Tap → expand. Swipe
/// down → dismiss. Swipe up → full detail sheet.
public struct ExperienceCardView: View {
    let experience: Experience
    var onExpand: () -> Void
    var onDismiss: () -> Void

    @GestureState private var dragTranslation: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var didCrossThreshold = false
    @State private var hasPreparedFeedback = false
    @State private var isPulsing = false

    // Pre-allocated so prepare() can be called once when the drag starts.
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let accentGold = Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255)

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

    /// Fades in both directions: downward (dismiss) and upward (expand).
    private var dragOpacity: Double {
        1 - min(0.4, abs(dragOffset) / 300)
    }

    private var isFavorited: Bool {
        preferences.favoritedExperiences.contains(experience.id)
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
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3)) {
                        preferences.toggleFavorite(experience.id)
                    }
                } label: {
                    let favorited = preferences.isFavorited(experience.id)
                    Image(systemName: favorited ? "heart.fill" : "heart")
                        .foregroundStyle(favorited ? Color.red : Color.secondary)
                        .frame(width: 32, height: 32)
                        .scaleEffect(favorited ? 1.15 : 1.0)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preferences.isFavorited(experience.id)
                    ? NSLocalizedString("card.favorite.remove", comment: "Remove from favorites")
                    : NSLocalizedString("card.favorite.add", comment: "Add to favorites"))
                ConfidenceBadge(confidence: experience.confidence, compact: true)
            }

            Text(experience.oneLiner)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)

            HStack {
                SoloScoreBadge(score: experience.soloScore, style: .compact)
                if experience.isBestNow() {
                    bestNowBadge
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
        .offset(y: dragOffset)
        .opacity(dragOpacity)
        .gesture(
            DragGesture(minimumDistance: 20)
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation.height
                }
                .onChanged { value in
                    let translation = value.translation.height
                    // Commit live position to dragOffset so snap-back can animate from here.
                    dragOffset = rubberBanded(translation)
                    if !hasPreparedFeedback {
                        hasPreparedFeedback = true
                        feedbackGenerator.prepare()
                    }
                    if !didCrossThreshold && abs(translation) > 60 {
                        didCrossThreshold = true
                        feedbackGenerator.impactOccurred()
                    }
                }
                .onEnded { value in
                    didCrossThreshold = false
                    hasPreparedFeedback = false
                    if value.translation.height > 60 {
                        dragOffset = 0
                        onDismiss()
                    } else if value.translation.height < -60 {
                        dragOffset = 0
                        onExpand()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(
            "\(experience.title). \(experience.oneLiner). " +
            String(format: NSLocalizedString("solo.a11y", comment: "Solo Score %@ of 10"),
                   String(format: "%.1f", experience.soloScore.overall))
        ))
        .accessibilityHint(Text(NSLocalizedString("experience.card.hint", comment: "Double tap to view details")))
        .accessibilityAction(
            named: Text(isFavorited
                ? NSLocalizedString("action.unfavorite", comment: "Remove favorite")
                : NSLocalizedString("action.favorite", comment: "Add favorite"))
        ) {
            preferences.toggleFavorite(experience.id)
        }
    }

    @ViewBuilder
    private var bestNowBadge: some View {
        Label(NSLocalizedString("experience.bestNow", comment: ""), systemImage: "sparkle")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Self.accentGold)
            .background(
                ZStack {
                    Capsule()
                        .fill(Self.accentGold.opacity(0.25))
                        .scaleEffect(isPulsing ? 1.12 : 1.0)
                        .opacity(isPulsing ? 0.0 : 0.5)
                        .blur(radius: 4)
                    Capsule()
                        .fill(Self.accentGold.opacity(0.2))
                }
            )
            .opacity(isPulsing ? 0.75 : 1.0)
            .scaleEffect(isPulsing ? 0.97 : 1.0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced {
                    withAnimation(.default) { isPulsing = false }
                } else {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
            }
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
        .environment(UserPreferences(defaults: UserDefaults(suiteName: "preview")!))
    } else {
        Text("No seed data")
    }
}

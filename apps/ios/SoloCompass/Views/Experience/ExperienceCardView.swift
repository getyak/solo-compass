import SwiftUI

/// Floating card that slides up when a marker is tapped. Tap → expand. Swipe
/// down → dismiss. Swipe up → full detail sheet.
public struct ExperienceCardView: View {
    let experience: Experience
    var onExpand: () -> Void
    var onDismiss: () -> Void

    public init(
        experience: Experience,
        onExpand: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.experience = experience
        self.onExpand = onExpand
        self.onDismiss = onDismiss
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
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height > 60 {
                        onDismiss()
                    } else if value.translation.height < -60 {
                        onExpand()
                    }
                }
        )
        .onTapGesture { onExpand() }
        .onAppear {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

#Preview {
    let exp = ExperienceService.hardcodedSeed.first!
    return VStack {
        Spacer()
        ExperienceCardView(
            experience: exp,
            onExpand: {},
            onDismiss: {}
        )
    }
    .background(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255))
}

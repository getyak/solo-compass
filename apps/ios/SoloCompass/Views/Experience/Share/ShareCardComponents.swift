import SwiftUI

// Shared sub-components used by the four ShareCardView_* variants.
// Sized in the /2 render coordinate system (ImageRenderer.scale=2 produces full-pixel PNG).

struct ScoreBadge: View {
    let score100: Int
    let isLarge: Bool

    var body: some View {
        HStack(spacing: isLarge ? 6 : 4) {
            Text("★")
                .font(.system(size: isLarge ? 36 : 22, weight: .black))
                .foregroundStyle(.yellow)
            Text("\(score100)")
                .font(.system(size: isLarge ? 60 : 32, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("/100")
                .font(.system(size: isLarge ? 22 : 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, isLarge ? 6 : 4)
        }
    }
}

struct HighlightBullet: View {
    let text: String
    let fontSize: CGFloat
    let onLightBackground: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(onLightBackground ? Color.black.opacity(0.6) : Color.white.opacity(0.9))
                .frame(width: fontSize * 0.25, height: fontSize * 0.25)
                .padding(.top, fontSize * 0.45)
            Text(text)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(onLightBackground ? Color.black.opacity(0.85) : Color.white.opacity(0.95))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}

struct BrandFooter: View {
    let handle: String
    let onLightBackground: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: 16, weight: .bold))
            Text("Solo Compass")
                .font(.system(size: 14, weight: .bold))
            Spacer()
            Text(handle)
                .font(.system(size: 12, weight: .medium))
                .opacity(0.7)
        }
        .foregroundStyle(onLightBackground ? Color.black.opacity(0.75) : Color.white.opacity(0.85))
    }
}

/// Bottom-third gradient overlay so white text stays legible over rich hero artwork.
struct ReadabilityScrim: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.0),
                Color.black.opacity(0.35),
                Color.black.opacity(0.55)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Emoji + 135° gradient hero. Used in every card style as the default visual.
struct GradientHero: View {
    let category: ExperienceCategory
    let emojiSize: CGFloat

    var body: some View {
        ZStack {
            CategoryVisual.gradient(for: category)
            // White radial highlight so the emoji doesn't look glued to the gradient.
            RadialGradient(
                colors: [Color.white.opacity(0.18), Color.white.opacity(0.0)],
                center: .center,
                startRadius: 0,
                endRadius: emojiSize
            )
            Text(CategoryVisual.emoji(for: category))
                .font(.system(size: emojiSize))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 4)
        }
    }
}

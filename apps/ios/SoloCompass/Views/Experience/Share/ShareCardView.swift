import SwiftUI

/// Dispatcher that picks the right concrete card view for a given style.
/// Sized at `style.renderSize` (half-pixel) — caller is responsible for any further scaling.
struct ShareCardView: View {
    let payload: ShareCardPayload
    let style: ShareCardStyle

    var body: some View {
        Group {
            switch style {
            case .xiaohongshuPortrait: XiaohongshuPortraitCard(payload: payload)
            case .twitterLandscape:    TwitterLandscapeCard(payload: payload)
            case .instagramSquare:     InstagramSquareCard(payload: payload)
            case .minimalText:         MinimalTextCard(payload: payload)
            }
        }
        .frame(width: style.renderSize.width, height: style.renderSize.height)
    }
}

// MARK: - Xiaohongshu / IG Story portrait (1080×1920)

struct XiaohongshuPortraitCard: View {
    let payload: ShareCardPayload

    var body: some View {
        // /2 coordinates: 540 × 960. Safe zones: top 125, bottom 140.
        ZStack(alignment: .bottomLeading) {
            GradientHero(category: payload.category, emojiSize: 180)
                .frame(width: 540, height: 960)

            ReadabilityScrim()
                .frame(width: 540, height: 960)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(CategoryVisual.emoji(for: payload.category))
                        .font(.system(size: 18))
                    Text(payload.category.localizedTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.ultraThinMaterial))
                .padding(.bottom, 16)

                Text(payload.title)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
                    .padding(.bottom, 8)

                if !payload.oneLiner.isEmpty {
                    Text(payload.oneLiner)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                        .padding(.bottom, 20)
                }

                ScoreBadge(score100: payload.score100, isLarge: true)
                    .padding(.bottom, 24)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(payload.highlights.prefix(3), id: \.self) { line in
                        HighlightBullet(text: line, fontSize: 20, onLightBackground: false)
                    }
                }
                .padding(.bottom, 24)

                if let place = payload.placeLabel, !place.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 16))
                        Text(place)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 20)
                }

                BrandFooter(handle: payload.brandHandle, onLightBackground: false)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 70)
        }
        .background(Color.black)
        .clipped()
    }
}

// MARK: - Twitter / OG landscape (1200×628)

struct TwitterLandscapeCard: View {
    let payload: ShareCardPayload

    var body: some View {
        // /2 coordinates: 600 × 314. Edge safety: ≥24 to avoid X crop.
        HStack(spacing: 0) {
            GradientHero(category: payload.category, emojiSize: 110)
                .frame(width: 240, height: 314)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(CategoryVisual.emoji(for: payload.category))
                        .font(.system(size: 14))
                    Text(payload.category.localizedTitle.uppercased())
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                }

                Text(payload.title)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if !payload.oneLiner.isEmpty {
                    Text(payload.oneLiner)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("★")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(.yellow)
                        Text("\(payload.score100)")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("/100")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 2)
                    }
                    if let place = payload.placeLabel, !place.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 12))
                            Text(place)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                BrandFooter(handle: payload.brandHandle, onLightBackground: true)
            }
            .padding(24)
            .frame(width: 360, height: 314, alignment: .topLeading)
            .background(Color(.systemBackground))
        }
        .frame(width: 600, height: 314)
        .background(Color(.systemBackground))
        .clipped()
    }
}

// MARK: - Instagram square (1080×1080)

struct InstagramSquareCard: View {
    let payload: ShareCardPayload

    var body: some View {
        // /2 coordinates: 540 × 540.
        VStack(spacing: 0) {
            GradientHero(category: payload.category, emojiSize: 140)
                .frame(width: 540, height: 324)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        Text(CategoryVisual.emoji(for: payload.category))
                            .font(.system(size: 16))
                        Text(payload.category.localizedTitle)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .padding(20)
                }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(payload.title)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(payload.score100)")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(payload.category.color)
                        Text("/100")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if let place = payload.placeLabel, !place.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 11))
                        Text(place)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(payload.highlights.prefix(2), id: \.self) { line in
                        HighlightBullet(text: line, fontSize: 12, onLightBackground: true)
                    }
                }

                Spacer(minLength: 2)
                BrandFooter(handle: payload.brandHandle, onLightBackground: true)
            }
            .padding(20)
            .frame(width: 540, height: 216, alignment: .topLeading)
            .background(Color(.systemBackground))
        }
        .frame(width: 540, height: 540)
        .background(Color(.systemBackground))
        .clipped()
    }
}

// MARK: - Minimal text (1080×1920, no hero photo)

struct MinimalTextCard: View {
    let payload: ShareCardPayload

    var body: some View {
        // /2 coordinates: 540 × 960. Full gradient + giant emoji + big type.
        ZStack {
            CategoryVisual.gradient(for: payload.category)
            RadialGradient(
                colors: [Color.white.opacity(0.15), Color.white.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.32),
                startRadius: 0,
                endRadius: 280
            )

            VStack(spacing: 0) {
                Spacer(minLength: 180)

                Text(CategoryVisual.emoji(for: payload.category))
                    .font(.system(size: 200))
                    .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
                    .padding(.bottom, 36)

                Text(payload.title)
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 48)
                    .padding(.bottom, 24)

                HStack(spacing: 8) {
                    Text("★")
                        .font(.system(size: 26, weight: .black))
                        .foregroundStyle(.yellow)
                    Text("\(payload.score100)")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("/100  Solo Score")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.bottom, 4)
                }
                .padding(.bottom, 16)

                if let place = payload.placeLabel, !place.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 14))
                        Text(place)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.9))
                }

                Spacer(minLength: 100)

                BrandFooter(handle: payload.brandHandle, onLightBackground: false)
                    .padding(.horizontal, 48)
                    .padding(.bottom, 70)
            }
        }
        .frame(width: 540, height: 960)
        .clipped()
    }
}

// MARK: - Previews

#if DEBUG
private func makePreviewPayload() -> ShareCardPayload {
    ShareCardPayload(
        title: "鸭川河畔散步",
        category: .nature,
        oneLiner: "Sunset walk along the Kamogawa with locals on benches",
        soloScore: 8.7,
        highlights: [
            "Walk south from Sanjo Bridge",
            "Grab a 7-Eleven onigiri",
            "Sit between two locals — that's the etiquette"
        ],
        placeLabel: "Kyoto",
        coordinate: ShareCardPayload.Coordinate(lon: 135.7693, lat: 35.0116)
    )
}

#Preview("Xiaohongshu 9:16") {
    ShareCardView(payload: makePreviewPayload(), style: .xiaohongshuPortrait)
        .border(Color.gray.opacity(0.3))
}

#Preview("Twitter 1.91:1") {
    ShareCardView(payload: makePreviewPayload(), style: .twitterLandscape)
        .border(Color.gray.opacity(0.3))
}

#Preview("Instagram 1:1") {
    ShareCardView(payload: makePreviewPayload(), style: .instagramSquare)
        .border(Color.gray.opacity(0.3))
}

#Preview("Minimal Text") {
    ShareCardView(payload: makePreviewPayload(), style: .minimalText)
        .border(Color.gray.opacity(0.3))
}
#endif

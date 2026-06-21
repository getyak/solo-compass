import SwiftUI

/// The floating preview shown above the native `.contextMenu` when a traveler
/// long-presses a place card. Surfaces the decision-relevant essentials —
/// a hero image (or category fallback), the short place name, its one-liner,
/// the Solo score, the live "best now" state, and walking distance — so they can
/// judge a spot without opening the full detail sheet.
///
/// Read-only by design: a context-menu preview must not contain its own tap
/// targets (the menu items below own the actions), so every badge here is static.
/// DayPage warm-amber system (CT tokens).
struct ExperiencePreviewCard: View {
    let experience: Experience
    let distanceMeters: Double?
    /// Live best-now / closing-soon chip state, resolved by the caller from the
    /// shared clock. Nil hides the chip.
    var bestNowChipState: BestNowChipState? = nil

    /// Short, human place name — never the long `title` sentence.
    private var placeName: String {
        experience.location.placeNameRomanized
            ?? experience.location.placeNameLocal
            ?? experience.title
    }

    private var walkMinutes: Int? {
        guard let m = distanceMeters else { return nil }
        // ~80 m/min walking pace, floored to a sensible minimum of 1.
        return max(1, Int((m / 80).rounded()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            details
        }
        .frame(width: 260)
        .background(CT.surfaceWhite)
    }

    // MARK: - Hero image (or category fallback)

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            heroImage
                .frame(width: 260, height: 146)
                .clipped()

            // Category chip (top-left) + best-now chip (top-right) float over the
            // image so they stay legible on any photo.
            HStack(alignment: .top) {
                categoryChip
                Spacer()
                if let chip = bestNowChipState {
                    bestNowChip(chip)
                }
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private var heroImage: some View {
        if let urlString = experience.location.photoUrls?.first,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty:
                    ZStack {
                        experience.category.color.opacity(0.16)
                        ProgressView().tint(experience.category.color)
                    }
                case .failure:
                    categoryFallback
                @unknown default:
                    categoryFallback
                }
            }
        } else {
            categoryFallback
        }
    }

    /// A warm category-tinted panel with a large glyph when no photo is available.
    private var categoryFallback: some View {
        ZStack {
            LinearGradient(
                colors: [experience.category.color.opacity(0.28), experience.category.color.opacity(0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: experience.category.symbol)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(experience.category.color)
        }
    }

    private var categoryChip: some View {
        HStack(spacing: 5) {
            Image(systemName: experience.category.symbol)
                .font(.system(size: 10, weight: .bold))
            Text(experience.category.localizedTitle)
                .font(CT.body(11, .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(experience.category.color.opacity(0.92)))
    }

    private func bestNowChip(_ chip: BestNowChipState) -> some View {
        HStack(spacing: 4) {
            Image(systemName: chip.symbol).font(.system(size: 9, weight: .bold))
            Text(chip.label).font(CT.body(10.5, .semibold))
        }
        .foregroundStyle(chip.foreground)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(chip.background))
        // <15min urgency pulse: subtle breathing scale so the chip catches
        // the eye without strobing. Honors reduceMotion (UrgencyPulse no-ops).
        .modifier(UrgencyPulse(active: chip.isUrgent))
    }

    // MARK: - Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(placeName)
                .font(CT.displayRounded(17, .semibold))
                .foregroundStyle(CT.fgPrimary)
                .lineLimit(1)

            if !experience.oneLiner.isEmpty {
                Text(experience.oneLiner)
                    .font(CT.body(13))
                    .foregroundStyle(CT.fgMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            keyInfoRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    /// Solo score · walking distance — the two numbers a traveler scans first.
    private var keyInfoRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "figure.stand")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CT.verifiedGreen)
                Text(String(format: "Solo %.1f", experience.soloScore.overall))
                    .font(CT.mono(12, .medium))
                    .foregroundStyle(CT.verifiedGreen)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(CT.verifiedGreen.opacity(0.1)))

            if let mins = walkMinutes {
                HStack(spacing: 4) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CT.fgMuted)
                    Text(String(format: NSLocalizedString("nearby.chip.walkMin", comment: "Walk minutes chip, e.g. '4 min'"), mins))
                        .font(CT.mono(12, .medium))
                        .foregroundStyle(CT.fgMuted)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(CT.surfaceSunken))
            }

            Spacer(minLength: 0)
        }
    }
}

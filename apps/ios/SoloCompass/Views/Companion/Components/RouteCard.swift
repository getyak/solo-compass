import SwiftUI

// MARK: - RouteCard

/// Single row in the 路线 section of BottomInfoSheet.
///
/// Layout: 44×44 gradient cover (left) | title + mono baseline (right) |
/// small verified corner pill when route.verification.status == .verified.
/// P0: no companion info shown.
public struct RouteCard: View {
    let route: Route

    private var monoBaseline: String {
        let dur = route.estimatedDuration >= 60
            ? String(format: "%dh%02dm", route.estimatedDuration / 60, route.estimatedDuration % 60)
            : "\(route.estimatedDuration)min"
        let dist = route.distanceMeters >= 1000
            ? String(format: "%.1fkm", Double(route.distanceMeters) / 1000)
            : "\(route.distanceMeters)m"
        return "\(dur) · \(dist) · \(route.pace.localizedLabel)"
    }

    private var isVerified: Bool {
        route.verification.status == .verified
    }

    public var body: some View {
        HStack(spacing: 10) {
            coverSquare

            VStack(alignment: .leading, spacing: 3) {
                Text(route.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(monoBaseline)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !stopColors.isEmpty {
                    stopStrip
                }
            }

            Spacer(minLength: 4)

            if isVerified {
                verifiedPill
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(route.title + ", " + monoBaseline))
    }

    // MARK: - Stop-strip breadcrumb (CompareCanvas A-001)

    /// One disc per stop (one per `experienceIds` entry). The first stop takes the
    /// route's primary-category color; later stops cycle the `CategoryVisual` palette
    /// so the journey reads as a sequence at a glance. Exposed for tests.
    var stopColors: [Color] {
        guard !route.experienceIds.isEmpty else { return [] }
        let palette = ExperienceCategory.allCases
        let startIndex = palette.firstIndex(of: primaryCategory) ?? 0
        return route.experienceIds.indices.map { offset in
            let category = palette[(startIndex + offset) % palette.count]
            return CategoryVisual.colorPair(for: category).0
        }
    }

    /// Horizontal breadcrumb: colored discs joined by 1px `CT.fgSubtle` connectors.
    private var stopStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(stopColors.enumerated()), id: \.offset) { offset, color in
                if offset > 0 {
                    Rectangle()
                        .fill(CT.fgSubtle)
                        .frame(width: 8, height: 1)
                }
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    // MARK: - Cover square

    private var coverSquare: some View {
        ZStack {
            CategoryVisual.gradient(for: primaryCategory)
            Text(CategoryVisual.emoji(for: primaryCategory))
                .font(.system(size: 20))
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Verified corner pill

    private var verifiedPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(NSLocalizedString("route.card.verified", comment: "Verified pill"))
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(CT.accent))
    }

    // MARK: - Derive primary category from route tags or fallback

    private var primaryCategory: ExperienceCategory {
        // Use first matching tag; fallback to .hidden so the gradient is always valid.
        let tagMap: [String: ExperienceCategory] = [
            "culture": .culture, "food": .food, "coffee": .coffee,
            "nature": .nature, "work": .work, "wellness": .wellness, "nightlife": .nightlife
        ]
        for tag in route.tags {
            if let cat = tagMap[tag.lowercased()] { return cat }
        }
        return .hidden
    }
}

// MARK: - Preview

#Preview("RouteCard — verified") {
    let route = Route(
        id: RouteId(rawValue: "r1"),
        title: "Mekong Sunset Walk",
        summary: "Promenade along the river.",
        experienceIds: ["e1", "e2"],
        cityCode: "VTE",
        region: "Riverfront",
        estimatedDuration: 90,
        distanceMeters: 1200,
        pace: .relaxed,
        tags: ["nature"],
        source: .editorial,
        bestNow: true,
        verification: RouteVerification(status: .verified, walkedByCount: 12, walkedBy: [])
    )
    RouteCard(route: route)
        .padding()
        .background(Color(.systemBackground))
}

#Preview("RouteCard — not verified") {
    let route = Route(
        id: RouteId(rawValue: "r2"),
        title: "Old Quarter Night Circuit",
        summary: "Street food, temples, and neon.",
        experienceIds: ["e3", "e4", "e5"],
        cityCode: "HAN",
        region: "Old Quarter",
        estimatedDuration: 45,
        distanceMeters: 800,
        pace: .packed,
        tags: ["food"],
        source: .aiGenerated,
        verification: RouteVerification(status: .walkedBy, walkedByCount: 3, walkedBy: [])
    )
    RouteCard(route: route)
        .padding()
        .background(Color(.systemBackground))
}

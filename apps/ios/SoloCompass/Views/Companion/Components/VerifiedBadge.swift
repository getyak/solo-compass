import SwiftUI

// MARK: - VerifiedBadge

/// Small "verified route" badge shown in route detail.
///
/// - `.badge` style (default): white card with glyph, title, subtitle, and AvatarStack.
/// - `.header` and `.inline` stubs return EmptyView for now.
public struct VerifiedBadge: View {
    let route: Route
    var style: VerifiedStyle = .badge

    private var isVerified: Bool {
        route.verification.status == .verified
    }

    private var walkedByCount: Int {
        route.verification.walkedByCount
    }

    private var walkedByIds: [String] {
        route.verification.walkedBy
    }

    public init(route: Route, style: VerifiedStyle = .badge) {
        self.route = route
        self.style = style
    }

    public var body: some View {
        switch style {
        case .badge:
            badgeBody
        case .header:
            headerBody
        case .inline:
            inlineBody
        }
    }

    // MARK: - Card style (default — independent card below hero)

    private var badgeBody: some View {
        HStack(spacing: 10) {
            glyphIcon
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isVerified ? CT.accent : CT.fgMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text(isVerified
                    ? NSLocalizedString("verified.title.verified", comment: "")
                    : NSLocalizedString("verified.title.watching", comment: ""))
                    .font(CT.display(13, .semibold))
                    .foregroundStyle(CT.fgPrimary)

                Text(String(
                    format: NSLocalizedString("verified.subtitle", comment: ""),
                    walkedByCount
                ))
                    .font(CT.body(12))
                    .foregroundStyle(CT.fgMuted)
            }

            Spacer(minLength: 0)

            if !walkedByIds.isEmpty {
                AvatarStack(ids: walkedByIds, maxVisible: 4, size: 22)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(CT.accentBorder, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Header style (strong — top status banner)

    private var headerBody: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)

            Text(isVerified
                ? NSLocalizedString("verified.title.verified", comment: "")
                : NSLocalizedString("verified.title.watching", comment: ""))
                .font(CT.display(12, .semibold))
                .foregroundStyle(Color.white)

            Spacer(minLength: 4)

            if !walkedByIds.isEmpty {
                AvatarStack(ids: walkedByIds, maxVisible: 4, size: 18, ring: isVerified ? CT.toneCompleted : CT.fgMuted)
            }
            Text(String(
                format: NSLocalizedString("verified.subtitle", comment: ""),
                walkedByCount
            ))
                .font(CT.mono(10, .medium))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isVerified ? CT.toneCompleted : CT.fgMuted)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Inline style (quietest — text-flow pill)

    private var inlineBody: some View {
        HStack(spacing: 4) {
            Image(systemName: isVerified ? "checkmark.circle.fill" : "person.2.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(String(
                format: NSLocalizedString("verified.inline", comment: ""),
                isVerified
                    ? NSLocalizedString("verified.short.verified", comment: "")
                    : NSLocalizedString("verified.short.watching", comment: ""),
                walkedByCount
            ))
                .font(CT.body(11, .medium))
        }
        .foregroundStyle(isVerified ? CT.toneCompleted : CT.fgMuted)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill((isVerified ? CT.toneCompleted : CT.fgMuted).opacity(0.10))
        )
        .accessibilityElement(children: .combine)
    }

    private var glyphIcon: Image {
        if isVerified {
            return Image(systemName: "checkmark.circle")
        } else {
            return Image(systemName: "person.2")
        }
    }
}

// MARK: - Preview

#Preview("Verified route") {
    let route = Route(
        id: RouteId(rawValue: "r1"),
        title: "京都东山漫步",
        summary: "From Kiyomizudera to Gion — the classic solo walk.",
        experienceIds: ["e1", "e2", "e3"],
        cityCode: "kyoto",
        region: "Kansai",
        estimatedDuration: 120,
        distanceMeters: 3200,
        pace: .relaxed,
        source: .editorial,
        verification: RouteVerification(
            status: .verified,
            walkedByCount: 47,
            walkedBy: ["alice", "bob", "carol", "dave", "eve"]
        )
    )
    VerifiedBadge(route: route)
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Watching route") {
    let route = Route(
        id: RouteId(rawValue: "r2"),
        title: "大阪道顿堀夜游",
        summary: "Neon, takoyaki, and street energy after dark.",
        experienceIds: ["e4", "e5"],
        cityCode: "osaka",
        region: "Kansai",
        estimatedDuration: 90,
        distanceMeters: 2100,
        pace: .standard,
        source: .aiGenerated,
        verification: RouteVerification(
            status: .walkedBy,
            walkedByCount: 8,
            walkedBy: ["frank", "grace"]
        )
    )
    VerifiedBadge(route: route)
        .padding()
        .background(Color(.systemGroupedBackground))
}

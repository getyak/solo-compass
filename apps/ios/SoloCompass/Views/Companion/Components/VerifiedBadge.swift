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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isVerified ? CT.verifiedGreen : CT.fgMuted)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isVerified
                            ? CT.verifiedGreen.opacity(0.14)
                            : CT.surfaceSunken)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(isVerified
                    ? NSLocalizedString("verified.title.verified", comment: "")
                    : NSLocalizedString("verified.title.watching", comment: ""))
                    .font(CT.display(13, .semibold))
                    .foregroundStyle(isVerified ? CT.verifiedGreen : CT.fgPrimary)

                Text(String(
                    format: NSLocalizedString("verified.subtitle", comment: ""),
                    walkedByCount
                ))
                    .font(CT.body(12))
                    .foregroundStyle(CT.fgMuted)
            }

            Spacer(minLength: 0)

            if !walkedByIds.isEmpty {
                AvatarStack(ids: walkedByIds, maxVisible: 5, size: 24)
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
                .fill(isVerified ? CT.verifiedGreenDot : Color.white)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .strokeBorder(
                            isVerified
                                ? CT.verifiedGreenDot.opacity(0.18)
                                : Color.clear,
                            lineWidth: 3
                        )
                )

            Text(isVerified
                ? NSLocalizedString("verified.title.verified", comment: "")
                : NSLocalizedString("verified.title.watching", comment: ""))
                .font(CT.display(12, .semibold))
                .foregroundStyle(isVerified ? CT.verifiedGreen : CT.fgMuted)

            Spacer(minLength: 4)

            if !walkedByIds.isEmpty {
                AvatarStack(ids: walkedByIds, maxVisible: 4, size: 18, ring: Self.headerRing)
            }
            Text(String(
                format: NSLocalizedString("verified.subtitle", comment: ""),
                walkedByCount
            ))
                .font(CT.mono(10, .medium))
                .foregroundStyle((isVerified ? CT.verifiedGreen : CT.fgMuted).opacity(0.85))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(headerBackground)
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
        .foregroundStyle(isVerified ? CT.verifiedGreen : CT.fgMuted)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(isVerified
                ? CT.verifiedGreen.opacity(0.12)
                : CT.surfaceSunken)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Header helpers

    /// Constant warm ring around header avatars, both verified and unverified states.
    private static let headerRing = Color(red: 250.0 / 255.0, green: 250.0 / 255.0, blue: 247.0 / 255.0) // #FAFAF7

    @ViewBuilder
    private var headerBackground: some View {
        if isVerified {
            LinearGradient(
                colors: [
                    CT.verifiedGreen.opacity(0.12),
                    CT.verifiedGreen.opacity(0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            CT.surfaceWhite
        }
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

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
            EmptyView()
        case .inline:
            EmptyView()
        }
    }

    // MARK: - Badge style

    private var badgeBody: some View {
        HStack(spacing: 10) {
            glyphIcon
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isVerified ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(isVerified
                    ? NSLocalizedString("verified.title.verified", comment: "")
                    : NSLocalizedString("verified.title.watching", comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(String(
                    format: NSLocalizedString("verified.subtitle", comment: ""),
                    walkedByCount
                ))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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
                        .strokeBorder(Color(hex: "#EDE8DF") ?? Color(.separator), lineWidth: 1)
                )
        )
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

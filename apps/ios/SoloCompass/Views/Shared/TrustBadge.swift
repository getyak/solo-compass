import SwiftUI

/// Provenance chip surfaced on Experience cards and detail hero. Reads
/// `experience.sources` + id prefix and picks one of five buckets so the
/// user can tell an Amap POI apart from an OSM POI at a glance — solving
/// the "every explored card looks identical" opacity that hid data
/// quality differences between sources.
///
/// Rendering: a colored dot + short label in a low-contrast capsule so it
/// reads as metadata (not a CTA). Sits at the trailing edge of card rows
/// and top-right of the detail hero.
public struct TrustBadge: View {

    public enum Level: Equatable {
        /// ≥2 distinct data sources agreed on this place. Strongest signal.
        case verified(sourceCount: Int)
        /// AutoNavi (高德) is the authoritative base. Mainland-China coverage.
        case amap
        /// OpenStreetMap contributor data.
        case osm
        /// The user registered this place themselves; unverified.
        case userCreated
        /// Curated seed entry — the app shipped with it.
        case curated

        var label: String {
            switch self {
            case .verified(let n):
                return String(
                    format: NSLocalizedString("trustBadge.verified", comment: "%d sources"),
                    n
                )
            case .amap:        return NSLocalizedString("trustBadge.amap", comment: "AutoNavi (Amap)")
            case .osm:         return NSLocalizedString("trustBadge.osm", comment: "OpenStreetMap")
            case .userCreated: return NSLocalizedString("trustBadge.user", comment: "User-added")
            case .curated:     return NSLocalizedString("trustBadge.curated", comment: "Curated")
            }
        }

        var dotColor: Color {
            switch self {
            case .verified:    return CT.verifiedGreenDot
            case .amap:        return Color(red: 0x1D / 255, green: 0x6F / 255, blue: 0xCC / 255) // AutoNavi blue
            case .osm:         return CT.sunGold
            case .userCreated: return CT.fgSubtle
            case .curated:     return CT.fgMuted
            }
        }

        var textColor: Color {
            switch self {
            case .verified:    return CT.verifiedGreen
            case .amap:        return Color(red: 0x14 / 255, green: 0x50 / 255, blue: 0x9C / 255) // deeper AutoNavi
            case .osm:         return CT.sunGoldDeep
            case .userCreated: return CT.fgMuted
            case .curated:     return CT.fgMuted
            }
        }
    }

    public enum Size {
        case compact  // row cards
        case full     // detail hero

        var dot: CGFloat { self == .compact ? 5 : 6 }
        var font: Font { self == .compact ? CT.mono(9.5, .semibold) : CT.mono(10.5, .semibold) }
        var hPad: CGFloat { self == .compact ? 6 : 8 }
        var vPad: CGFloat { self == .compact ? 3 : 4 }
    }

    public let level: Level
    public let size: Size

    public init(level: Level, size: Size = .compact) {
        self.level = level
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(level.dotColor)
                .frame(width: size.dot, height: size.dot)
            Text(level.label.uppercased())
                .font(size.font)
                .tracking(0.8)
                .foregroundStyle(level.textColor)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, size.hPad)
        .padding(.vertical, size.vPad)
        .background(
            Capsule(style: .continuous)
                .fill(level.dotColor.opacity(0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(level.dotColor.opacity(0.22), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("trustBadge.a11y", comment: "Data source: %@"),
            level.label
        )))
    }
}

// MARK: - Experience → TrustBadge.Level mapping

public extension Experience {
    /// Pick the strongest applicable badge level from this experience's
    /// provenance. Prefers "verified across multiple sources" over any
    /// single-source label when 2+ distinct source types are present.
    var trustBadgeLevel: TrustBadge.Level {
        let distinctSources = Set(sources.map(\.type))

        if distinctSources.count >= 2 {
            return .verified(sourceCount: distinctSources.count)
        }
        if distinctSources.contains(.amap) {
            return .amap
        }
        if isUserCreated {
            return .userCreated
        }
        if isFromOpenStreetMap {
            return .osm
        }
        return .curated
    }
}

#Preview("TrustBadge — all levels · compact") {
    VStack(alignment: .leading, spacing: 10) {
        TrustBadge(level: .verified(sourceCount: 3))
        TrustBadge(level: .verified(sourceCount: 2))
        TrustBadge(level: .amap)
        TrustBadge(level: .osm)
        TrustBadge(level: .userCreated)
        TrustBadge(level: .curated)
    }
    .padding(20)
    .background(CT.bgWarm)
}

#Preview("TrustBadge — detail hero · full") {
    VStack(alignment: .leading, spacing: 12) {
        TrustBadge(level: .verified(sourceCount: 3), size: .full)
        TrustBadge(level: .amap, size: .full)
        TrustBadge(level: .osm, size: .full)
    }
    .padding(20)
    .background(CT.bgWarm)
}

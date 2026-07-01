import SwiftUI

/// P3.2 #322: Solo Brag card. Screenshot-friendly composition —
/// numbers + one line + one anchor.
public struct BragCardView: View {

    public let data: BragCardData
    public let onShare: () -> Void
    public let onWallpaper: () -> Void
    public let onVideoUnlock: () -> Void
    public let isVideoUnlocked: Bool

    public init(
        data: BragCardData,
        isVideoUnlocked: Bool,
        onShare: @escaping () -> Void,
        onWallpaper: @escaping () -> Void,
        onVideoUnlock: @escaping () -> Void
    ) {
        self.data = data
        self.isVideoUnlocked = isVideoUnlocked
        self.onShare = onShare
        self.onWallpaper = onWallpaper
        self.onVideoUnlock = onVideoUnlock
    }

    public var body: some View {
        VStack(spacing: 22) {
            Text(data.cityCode.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.6)
                .foregroundColor(CT.omenGold)

            HStack(spacing: 20) {
                metric(value: "\(data.dayCount)", label: "days")
                metric(value: "\(data.distinctExperienceCount)", label: "places")
                metric(value: String(format: "%.1f", data.approxDistanceKm), label: "km")
            }

            Text(data.headline)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundColor(CT.fgPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if let anchor = data.anchorExperienceTitle {
                Text(anchor)
                    .font(.callout.italic())
                    .foregroundColor(CT.fgMuted)
            }

            Divider().padding(.horizontal, 40)

            HStack {
                Button(action: onShare) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.callout.weight(.semibold))
                }
                Spacer()
                Button(action: onWallpaper) {
                    Label("Wallpaper", systemImage: "iphone")
                        .font(.callout)
                        .foregroundColor(CT.fgMuted)
                }
                Spacer()
                Button(action: onVideoUnlock) {
                    Label(
                        isVideoUnlocked ? "Video" : "Video · $1.99",
                        systemImage: "video"
                    )
                    .font(.callout)
                    .foregroundColor(isVideoUnlocked ? CT.omenGold : CT.fgMuted)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(24)
        .background(CT.surfaceWhite)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
        .padding(20)
    }

    @ViewBuilder
    private func metric(value: String, label: String) -> some View {
        VStack {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(CT.fgPrimary)
            Text(label)
                .font(.caption)
                .foregroundColor(CT.fgMuted)
        }
    }
}

#Preview {
    BragCardView(
        data: .init(
            cityCode: "cmi",
            dayCount: 6,
            distinctExperienceCount: 12,
            approxDistanceKm: 22.4,
            flourishes: .init(coffeesConsumed: 9),
            headline: "CMI — went slow, on purpose.",
            anchorExperienceTitle: "Kalare market alley",
            createdAt: Date()
        ),
        isVideoUnlocked: false,
        onShare: {},
        onWallpaper: {},
        onVideoUnlock: {}
    )
}

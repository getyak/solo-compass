import SwiftUI

/// Glassmorphism pill shown at the top of CompassMapView while Overpass POIs
/// are being fetched (#134). Mirrors `OfflineBanner` so the two top banners
/// read as one visual family; uses a small spinner so the fetch reads as
/// "in progress" rather than an error/offline state.
struct POILoadingBanner: View {
    var body: some View {
        GlassmorphismCapsule(
            verticalPadding: 8,
            leading: {
                ProgressView()
                    .controlSize(.mini)
            },
            content: {
                Text(NSLocalizedString("map.loadingPOIs", comment: "Loading nearby places banner"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(NSLocalizedString("map.loadingPOIs", comment: "Loading nearby places banner")))
    }
}

#Preview {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        POILoadingBanner()
            .padding(.top, 60)
    }
}

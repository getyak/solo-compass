import SwiftUI

/// Glassmorphism pill shown at the top of CompassMapView while Overpass POIs
/// are being fetched (#134). Mirrors `OfflineBanner` so the two top banners
/// read as one visual family; uses a small spinner so the fetch reads as
/// "in progress" rather than an error/offline state.
struct POILoadingBanner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        GlassmorphismCapsule(
            verticalPadding: 8,
            leading: {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(isPulsing ? 1.08 : 0.92)
                    .opacity(isPulsing ? 1.0 : 0.6)
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
        .onAppear {
            UIAccessibility.post(
                notification: .announcement,
                argument: NSLocalizedString("map.loadingPOIs.a11yAnnouncement", comment: "VoiceOver announcement when POI fetch begins")
            )
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                withAnimation(.default) { isPulsing = false }
            } else {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        POILoadingBanner()
            .padding(.top, 60)
    }
}

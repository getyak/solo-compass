import SwiftUI

/// Glassmorphism pill shown at the top of CompassMapView while Overpass POIs
/// are being fetched (#134). Mirrors `OfflineBanner` so the two top banners
/// read as one visual family; uses a small spinner so the fetch reads as
/// "in progress" rather than an error/offline state.
struct POILoadingBanner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    @State private var isSlow: Bool
    @State private var slowTask: Task<Void, Never>?

    // `previewSlow` is only used in #Preview blocks to skip the 6-second wait.
    init(previewSlow: Bool = false) {
        _isSlow = State(initialValue: previewSlow)
    }

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
                Text(isSlow
                     ? NSLocalizedString("map.loadingPOIs.slow", comment: "Reassurance shown when POI fetch exceeds ~6 s")
                     : NSLocalizedString("map.loadingPOIs", comment: "Loading nearby places banner"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut, value: isSlow)
            }
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(isSlow
            ? NSLocalizedString("map.loadingPOIs.slow", comment: "Reassurance shown when POI fetch exceeds ~6 s")
            : NSLocalizedString("map.loadingPOIs", comment: "Loading nearby places banner")))
        .onAppear {
            UIAccessibility.post(
                notification: .announcement,
                argument: NSLocalizedString("map.loadingPOIs.a11yAnnouncement", comment: "VoiceOver announcement when POI fetch begins")
            )
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
            guard !isSlow else { return }
            slowTask = Task {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut) {
                    isSlow = true
                }
                UIAccessibility.post(
                    notification: .announcement,
                    argument: NSLocalizedString("map.loadingPOIs.slow", comment: "Reassurance shown when POI fetch exceeds ~6 s")
                )
            }
        }
        .onDisappear {
            slowTask?.cancel()
            slowTask = nil
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

#Preview("Slow") {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        POILoadingBanner(previewSlow: true)
            .padding(.top, 60)
    }
}

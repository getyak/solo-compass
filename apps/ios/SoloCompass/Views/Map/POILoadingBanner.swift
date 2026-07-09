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
    @State private var bannerState: BannerState = .loading
    @State private var loadedCount: Int = 0

    private enum BannerState {
        case loading, succeeded
    }

    // `previewSlow` is only used in #Preview blocks to skip the 6-second wait.
    // `previewDone` is only used in #Preview blocks to show the success state directly.
    init(previewSlow: Bool = false, previewDone: Bool = false) {
        _isSlow = State(initialValue: previewSlow)
        _bannerState = State(initialValue: previewDone ? .succeeded : .loading)
        _loadedCount = State(initialValue: previewDone ? 12 : 0)
    }

    @MainActor
    func showSuccess(count: Int) async {
        slowTask?.cancel()
        slowTask = nil

        withAnimation(reduceMotion ? nil : .easeInOut) {
            isPulsing = false
            loadedCount = count
            bannerState = .succeeded
        }

        Haptics.notify(.success)

        UIAccessibility.post(
            notification: .announcement,
            argument: String(format: NSLocalizedString("map.loadingPOIs.done", comment: "Shown for ~1.2 s after the Overpass fetch completes — %d = number of POIs found"), count)
        )

        try? await Task.sleep(nanoseconds: 1_200_000_000)
    }

    var body: some View {
        GlassmorphismCapsule(
            verticalPadding: 8,
            leading: {
                Group {
                    if bannerState == .succeeded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CT.verifiedGreen)
                            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(isPulsing ? 1.08 : 0.92)
                            .opacity(isPulsing ? 1.0 : 0.6)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: bannerState)
            },
            content: {
                Group {
                    if bannerState == .succeeded {
                        Text(String(format: NSLocalizedString("map.loadingPOIs.done", comment: "Shown for ~1.2 s after the Overpass fetch completes — %d = number of POIs found"), loadedCount))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CT.verifiedGreen)
                    } else {
                        Text(isSlow
                             ? NSLocalizedString("map.loadingPOIs.slow", comment: "Reassurance shown when POI fetch exceeds ~6 s")
                             : NSLocalizedString("map.loadingPOIs", comment: "Loading nearby places banner"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                            .animation(reduceMotion ? nil : .easeInOut, value: isSlow)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: bannerState)
            }
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            UIAccessibility.post(
                notification: .announcement,
                argument: NSLocalizedString("map.loadingPOIs.a11yAnnouncement", comment: "VoiceOver announcement when POI fetch begins")
            )
            guard !reduceMotion else { return }
            guard bannerState == .loading else { return }
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
            guard bannerState == .loading else { return }
            if reduced {
                withAnimation(.default) { isPulsing = false }
            } else {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
    }

    private var accessibilityLabel: Text {
        switch bannerState {
        case .succeeded:
            return Text(String(format: NSLocalizedString("map.loadingPOIs.done", comment: "Shown for ~1.2 s after the Overpass fetch completes — %d = number of POIs found"), loadedCount))
        case .loading:
            return Text(isSlow
                ? NSLocalizedString("map.loadingPOIs.slow", comment: "Reassurance shown when POI fetch exceeds ~6 s")
                : NSLocalizedString("map.loadingPOIs", comment: "Loading nearby places banner"))
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

#Preview("Done") {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        POILoadingBanner(previewDone: true)
            .padding(.top, 60)
    }
}

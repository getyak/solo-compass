import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Amber pill banner shown in CompassMapView when the app is offline and showing cached data (US-041).
/// When `onRetry` is non-nil the banner becomes a tappable button that re-runs the experience load.
struct OfflineBanner: View {
    var onRetry: (() async -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    @State private var isRetrying = false
    @State private var shakeOffset: CGFloat = 0
    @State private var retryFailed = false
    @State private var bannerState: BannerState = .offline

    private enum BannerState {
        case offline, retrying, recovered
    }

    var body: some View {
        pillContent
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(NSLocalizedString("offline.banner", comment: "Offline mode banner")))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced {
                    withAnimation(.default) { isPulsing = false }
                } else if bannerState == .offline {
                    withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
            }
            .onChange(of: NetworkMonitor.shared.isConnected) { wasConnected, isConnected in
                guard !wasConnected, isConnected, bannerState != .recovered else { return }
                Task { await handleRecovery() }
            }
    }

    @MainActor
    private func handleRecovery() async {
        withAnimation(.default) {
            isPulsing = false
            bannerState = .recovered
        }

        Haptics.notify(.success)

        UIAccessibility.post(
            notification: .announcement,
            argument: NSLocalizedString("offline.banner.recovered", comment: "Back online — connectivity restored")
        )

        try? await Task.sleep(nanoseconds: 1_200_000_000)
        // Parent dismiss logic will remove the banner; fade out as fallback if still visible
        withAnimation(.easeOut(duration: 0.3)) {
            bannerState = .offline
        }
    }

    @ViewBuilder
    private var pillContent: some View {
        if let onRetry, bannerState != .recovered {
            Button {
                guard !isRetrying else { return }
                Haptics.impact(.light)
                isRetrying = true
                bannerState = .retrying
                Task {
                    await onRetry()
                    let stillOffline = await MainActor.run { !NetworkMonitor.shared.isConnected }
                    if stillOffline {
                        await handleRetryFailure()
                    }
                    isRetrying = false
                    if bannerState == .retrying { bannerState = .offline }
                }
            } label: {
                capsuleView
                    .offset(x: shakeOffset)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text(NSLocalizedString("offline.banner.retry.hint", comment: "Double tap to retry connection")))
        } else {
            capsuleView
        }
    }

    @MainActor
    private func handleRetryFailure() async {
        Haptics.notify(.warning)

        UIAccessibility.post(
            notification: .announcement,
            argument: NSLocalizedString("offline.banner.retry.failed", comment: "Retry failed — still offline")
        )

        retryFailed = true

        if !reduceMotion {
            let steps: [(CGFloat, Double)] = [(-6, 0.07), (6, 0.07), (-4, 0.07), (4, 0.07), (0, 0.07)]
            for (offset, duration) in steps {
                withAnimation(.easeInOut(duration: duration)) {
                    shakeOffset = offset
                }
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            }
        }

        try? await Task.sleep(nanoseconds: 600_000_000)
        retryFailed = false
    }

    private var bannerColor: Color {
        switch bannerState {
        case .offline: return retryFailed ? CT.savedRed : CT.warningText
        case .retrying: return CT.warningText
        case .recovered: return CT.verifiedGreen
        }
    }

    @ViewBuilder
    private var capsuleView: some View {
        GlassmorphismCapsule(
            verticalPadding: 8,
            leading: {
                Group {
                    if isRetrying {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(CT.warningText)
                    } else if bannerState == .recovered {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(bannerColor)
                    } else {
                        Image(systemName: "wifi.slash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(bannerColor)
                            .scaleEffect(isPulsing ? 1.12 : 0.96)
                            .opacity(isPulsing ? 1.0 : 0.65)
                    }
                }
            },
            content: {
                HStack(spacing: 4) {
                    if bannerState == .recovered {
                        Text(NSLocalizedString("offline.banner.recovered", comment: "Back online — connectivity restored"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(bannerColor)
                    } else {
                        Text(NSLocalizedString("offline.banner", comment: "Offline mode banner"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(bannerColor)
                        if onRetry != nil && !isRetrying {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(bannerColor.opacity(0.7))
                            Text(NSLocalizedString("offline.banner.retry", comment: "Tap to retry connection"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(bannerColor.opacity(0.85))
                        }
                    }
                }
            }
        )
    }
}

#Preview {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        OfflineBanner()
            .padding(.top, 60)
    }
}

#Preview("With Retry") {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        OfflineBanner(onRetry: {
            try? await Task.sleep(for: .seconds(1))
        })
        .padding(.top, 60)
    }
}

#Preview("Reduce Motion") {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        OfflineBanner()
            .padding(.top, 60)
    }
}

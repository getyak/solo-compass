import SwiftUI

/// Amber pill banner shown in CompassMapView when the app is offline and showing cached data (US-041).
/// When `onRetry` is non-nil the banner becomes a tappable button that re-runs the experience load.
struct OfflineBanner: View {
    var onRetry: (() async -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    @State private var isRetrying = false

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
                } else {
                    withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
            }
    }

    @ViewBuilder
    private var pillContent: some View {
        if let onRetry {
            Button {
                guard !isRetrying else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isRetrying = true
                Task {
                    await onRetry()
                    isRetrying = false
                }
            } label: {
                capsuleView
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text(NSLocalizedString("offline.banner.retry.hint", comment: "Double tap to retry connection")))
        } else {
            capsuleView
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
                            .tint(Color.orange)
                    } else {
                        Image(systemName: "wifi.slash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.orange)
                            .scaleEffect(isPulsing ? 1.12 : 0.96)
                            .opacity(isPulsing ? 1.0 : 0.65)
                    }
                }
            },
            content: {
                HStack(spacing: 4) {
                    Text(NSLocalizedString("offline.banner", comment: "Offline mode banner"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.orange)
                    if onRetry != nil && !isRetrying {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(Color.orange.opacity(0.7))
                        Text(NSLocalizedString("offline.banner.retry", comment: "Tap to retry connection"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.orange.opacity(0.85))
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

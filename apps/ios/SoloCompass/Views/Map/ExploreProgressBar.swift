import SwiftUI

/// Inline progress capsule for the Pro multi-ring Explore (US-MR-04).
/// Sits above `BottomInfoBar` in `CompassMapView` and disappears as soon
/// as `exploreProgress` returns to `.idle` (success or fail).
/// Single-ring legacy Explore never sets a non-idle state, so this view
/// is invisible during those runs.
struct ExploreProgressBar: View {
    let progress: MapViewModel.ExploreProgress

    /// Derive display text; nil means the capsule should be hidden.
    var text: String? {
        CompassMapContentView.progressText(for: progress)
    }

    var body: some View {
        if let text {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(text)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.thinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            .transition(.opacity)
            .accessibilityIdentifier("exploreProgress")
            .accessibilityLabel(Text(text))
        }
    }
}

#Preview("Scanning ring 2 of 4") {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        VStack {
            Spacer()
            ExploreProgressBar(progress: .multiRingScanning(ringsDone: 2, totalRings: 4))
                .padding(.bottom, 100)
        }
    }
}

#Preview("Synthesizing 47 places") {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        VStack {
            Spacer()
            ExploreProgressBar(progress: .synthesizing(poiCount: 47))
                .padding(.bottom, 100)
        }
    }
}

#Preview("Idle — hidden") {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        VStack {
            Spacer()
            ExploreProgressBar(progress: .idle)
                .padding(.bottom, 100)
        }
    }
}

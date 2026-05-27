import SwiftUI

/// Shimmer loading placeholder. Supports `.redacted(reason: .placeholder)` integration
/// and configurable line count / width fractions.
public struct SkeletonView: View {
    let lineCount: Int
    let widthFractions: [CGFloat]

    public init(lineCount: Int = 3, widthFractions: [CGFloat]? = nil) {
        let clamped = max(1, lineCount)
        self.lineCount = clamped
        if let fractions = widthFractions, fractions.count == clamped {
            self.widthFractions = fractions
        } else {
            // Default: first lines full width, last line 60%
            self.widthFractions = (0..<clamped).map { i in
                i == clamped - 1 ? 0.6 : 1.0
            }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<lineCount, id: \.self) { i in
                SkeletonLine(widthFraction: widthFractions[i])
            }
        }
        .accessibilityLabel(Text(NSLocalizedString("skeleton.loading", comment: "Loading")))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct SkeletonLine: View {
    let widthFraction: CGFloat
    @State private var shimmerPhase: CGFloat = -1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 4)
                .fill(shimmerGradient(width: geo.size.width))
                .frame(width: geo.size.width * widthFraction, height: 14)
        }
        .frame(height: 14)
        .onAppear {
            startShimmer()
        }
        .onChange(of: reduceMotion) { _, _ in
            startShimmer()
        }
    }

    private func startShimmer() {
        guard !reduceMotion else {
            shimmerPhase = 0
            return
        }
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
            shimmerPhase = 1.0
        }
    }

    private func shimmerGradient(width: CGFloat) -> LinearGradient {
        let highlight = Color.white.opacity(0.6)
        let base = Color(uiColor: .systemGray5)
        let center = (shimmerPhase + 1) / 2
        return LinearGradient(
            stops: [
                .init(color: base, location: max(0, center - 0.3)),
                .init(color: highlight, location: center),
                .init(color: base, location: min(1, center + 0.3)),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - .redacted integration

extension View {
    /// Overlays a `SkeletonView` instead of the system `.redacted` blur when `isLoading` is true.
    public func skeletonRedacted(isLoading: Bool, lineCount: Int = 3) -> some View {
        overlay(
            Group {
                if isLoading {
                    SkeletonView(lineCount: lineCount)
                        .padding(.horizontal, 4)
                }
            }
        )
        .opacity(isLoading ? 0 : 1)
    }
}

#Preview("Reduce Motion") {
    VStack(alignment: .leading, spacing: 24) {
        Text("Reduce Motion — static placeholders")
            .font(.caption)
            .foregroundStyle(.secondary)

        SkeletonView(lineCount: 3)

        Divider()

        Text("Custom widths — no sweep")
            .font(.caption)
            .foregroundStyle(.secondary)

        SkeletonView(lineCount: 4, widthFractions: [1.0, 0.85, 0.9, 0.5])
    }
    .padding()
}

#Preview("3-line text skeleton") {
    VStack(alignment: .leading, spacing: 24) {
        Text("3-line default")
            .font(.caption)
            .foregroundStyle(.secondary)

        SkeletonView(lineCount: 3)

        Divider()

        Text("Custom widths")
            .font(.caption)
            .foregroundStyle(.secondary)

        SkeletonView(lineCount: 4, widthFractions: [1.0, 0.85, 0.9, 0.5])

        Divider()

        Text("skeletonRedacted modifier")
            .font(.caption)
            .foregroundStyle(.secondary)

        Text("Some content that would load here.")
            .skeletonRedacted(isLoading: true, lineCount: 2)
    }
    .padding()
}

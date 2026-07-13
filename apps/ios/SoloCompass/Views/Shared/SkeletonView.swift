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
        // Warm-amber shimmer instead of cold systemGray — the loading state is
        // one of the screens users stare at longest, and it should breathe the
        // same amber identity as the rest of the app (audit skeleton-01).
        // Base + highlight are adaptive so dark mode stays warm-charcoal, not gray.
        let highlight = CT.surfaceWhite.opacity(0.55)
        let base = CT.sheetAdaptive
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

// MARK: - Companion row skeleton

/// Single skeleton row matching the emoji-handle + blurb layout of companion list rows.
public struct CompanionRowSkeleton: View {
    public init() {}

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(CT.sheetAdaptive)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            SkeletonView(lineCount: 2, widthFractions: [1.0, 0.5])
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
    }
}

/// A non-interactive list of `CompanionRowSkeleton` rows with `.insetGrouped` spacing.
public struct CompanionSkeletonList: View {
    let rows: Int

    public init(rows: Int = 5) {
        self.rows = max(1, rows)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in
                CompanionRowSkeleton()
                Divider().padding(.leading, 64)
            }
        }
        .background(CT.cardAdaptive)
        .clipShape(Radius.shape(Radius.md))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(NSLocalizedString("skeleton.loading", comment: "Loading")))
        .accessibilityAddTraits(.updatesFrequently)
        .allowsHitTesting(false)
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

#Preview("Companion row skeleton") {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            Text("Loading state (5 rows)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            CompanionSkeletonList(rows: 5)
        }
    }
    .background(Color(uiColor: .systemGroupedBackground))
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

import SwiftUI

/// Dynamic "what's around right now" line at the bottom of the map.
/// The text is computed by `MapViewModel.updateBottomInfo()`; this view just
/// renders it with a subtle solo-traveler footprint count.
public struct BottomInfoBar: View {
    let text: String
    let nearbySoloCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Drives the insertion/removal transition — set via onChange so withAnimation wraps the flip.
    @State private var footprintVisible = false
    // Prevents the bounce from firing more than once across the view's lifetime.
    @State private var hasBouncedOnce = false

    public init(text: String, nearbySoloCount: Int) {
        self.text = text
        self.nearbySoloCount = nearbySoloCount
    }

    public var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: text)

            if footprintVisible {
                Spacer(minLength: 8)
                HStack(spacing: 3) {
                    Image(systemName: "figure.walk")
                        .font(.caption2)
                        // Bounce once on first detection; subsequent zero-crossings are silent.
                        .symbolEffect(.bounce, value: reduceMotion ? false : hasBouncedOnce)
                    Text("\(nearbySoloCount)")
                        .font(.caption.monospacedDigit())
                        // Roll the digit on count changes while the pill is already visible.
                        .contentTransition(reduceMotion ? .identity : .numericText(value: Double(nearbySoloCount)))
                        .animation(.snappy, value: nearbySoloCount)
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(String(
                    format: NSLocalizedString("info.nearbySolo.a11y", comment: "%d solo travelers passed nearby today"),
                    nearbySoloCount
                )))
                // Scale+fade entrance; plain cross-fade when Reduce Motion is on.
                .transition(reduceMotion
                    ? .opacity
                    : .scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .onAppear {
            footprintVisible = nearbySoloCount > 0
        }
        .onChange(of: nearbySoloCount) { _, newCount in
            let entering = newCount > 0
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                footprintVisible = entering
            }
            if entering && !hasBouncedOnce {
                hasBouncedOnce = true
            }
        }
    }
}

#Preview("With nearby solos") {
    VStack {
        Spacer()
        BottomInfoBar(
            text: "Sunset in 47 minutes. 2 perfect viewing spots within walking distance.",
            nearbySoloCount: 12
        )
    }
    .background(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255))
}

#Preview("No nearby solos") {
    VStack {
        Spacer()
        BottomInfoBar(
            text: "Quiet morning. Golden hour starts in 23 minutes.",
            nearbySoloCount: 0
        )
    }
    .background(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255))
}

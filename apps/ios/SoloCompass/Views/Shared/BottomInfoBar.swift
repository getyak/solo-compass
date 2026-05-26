import SwiftUI

/// Dynamic "what's around right now" line at the bottom of the map.
/// The text is computed by `MapViewModel.updateBottomInfo()`; this view just
/// renders it with a subtle solo-traveler footprint count.
public struct BottomInfoBar: View {
    let text: String
    let nearbySoloCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Tracks whether the footprint pill has been shown at least once (one-shot bounce guard).
    @State private var appeared = false
    // Drives the insertion animation; toggled whenever count crosses into positive.
    @State private var footprintVisible = false

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

            if nearbySoloCount > 0 {
                Spacer(minLength: 8)
                HStack(spacing: 3) {
                    Image(systemName: "figure.walk")
                        .font(.caption2)
                        // One-shot bounce when a fellow solo traveler is first detected.
                        .symbolEffect(.bounce, value: appeared && !reduceMotion ? nearbySoloCount > 0 : false)
                    Text("\(nearbySoloCount)")
                        .font(.caption.monospacedDigit())
                        // Roll the digit up on count changes; skip the roll with Reduce Motion.
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
            // Mark appeared so the bounce symbolEffect key is active from here on.
            appeared = true
        }
        .onChange(of: nearbySoloCount) { _, newCount in
            let entering = newCount > 0
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                footprintVisible = entering
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

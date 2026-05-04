import SwiftUI

/// Dynamic "what's around right now" line at the bottom of the map.
/// The text is computed by `MapViewModel.updateBottomInfo()`; this view just
/// renders it with a subtle solo-traveler footprint count.
public struct BottomInfoBar: View {
    let text: String
    let nearbySoloCount: Int

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
                    Text("\(nearbySoloCount)")
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("\(nearbySoloCount) solo travelers passed nearby today"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
    }
}

#Preview {
    VStack {
        Spacer()
        BottomInfoBar(
            text: "Sunset in 47 minutes. 2 perfect viewing spots within walking distance.",
            nearbySoloCount: 12
        )
    }
    .background(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255))
}

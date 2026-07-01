import SwiftUI

/// P2.3 #232: end-of-blindbox recap card. Screenshot-optimized — the
/// PRD calls out this surface as a viral share moment.
public struct BlindboxRecapCard: View {

    public struct RecapData: Hashable {
        public let anchorTitles: [String]
        public let approxDistanceKm: Double
        public let agentTagline: String
        public let cityCode: String

        public init(anchorTitles: [String], approxDistanceKm: Double, agentTagline: String, cityCode: String) {
            self.anchorTitles = anchorTitles
            self.approxDistanceKm = approxDistanceKm
            self.agentTagline = agentTagline
            self.cityCode = cityCode
        }
    }

    public let data: RecapData
    public let onShare: () -> Void

    public init(data: RecapData, onShare: @escaping () -> Void) {
        self.data = data
        self.onShare = onShare
    }

    public var body: some View {
        VStack(spacing: 20) {
            Text(data.cityCode.uppercased())
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundColor(CT.blindboxAmber)

            Text("\(data.anchorTitles.count) places")
                .font(.system(size: 40, weight: .bold, design: .serif))
                .foregroundColor(CT.fgPrimary)

            Text(String(format: "%.1f km walked", data.approxDistanceKm))
                .font(.callout)
                .foregroundColor(CT.fgMuted)

            Divider().padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(data.anchorTitles, id: \.self) { title in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(CT.sunGold)
                            .frame(width: 6, height: 6)
                        Text(title)
                            .font(.callout)
                            .foregroundColor(CT.fgPrimary)
                    }
                }
            }

            Text(data.agentTagline)
                .font(.system(size: 15, design: .serif))
                .italic()
                .foregroundColor(CT.fgMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: onShare) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(CT.blindboxAmber)
                    .foregroundColor(.white)
                    .cornerRadius(20)
                    .padding(.horizontal, 32)
            }
        }
        .padding(.vertical, 28)
        .background(CT.surfaceWhite)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
        .padding(20)
    }
}

#Preview {
    BlindboxRecapCard(
        data: .init(
            anchorTitles: ["Wat Phra Singh", "Kalare market alley", "One Nimman coffee window"],
            approxDistanceKm: 3.6,
            agentTagline: "You chose the slower path three times. It suited you.",
            cityCode: "cmi"
        ),
        onShare: {}
    )
}

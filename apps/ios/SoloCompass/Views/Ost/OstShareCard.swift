import SwiftUI

/// P3.1 #312: shareable "Today's OST" card. Screenshot-first design.
public struct OstShareCard: View {

    public let descriptor: OstPlaylistDescriptor
    public let onShare: () -> Void
    public let onRegenerate: () -> Void

    public init(
        descriptor: OstPlaylistDescriptor,
        onShare: @escaping () -> Void,
        onRegenerate: @escaping () -> Void
    ) {
        self.descriptor = descriptor
        self.onShare = onShare
        self.onRegenerate = onRegenerate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's OST")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundColor(CT.fgPrimary)
                Spacer()
                Text(descriptor.style.rawValue.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CT.omenGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CT.accentSoft)
                    .cornerRadius(8)
            }

            Text("\(descriptor.trackIDs.count) tracks · \(descriptor.visitCount) places")
                .font(.footnote)
                .foregroundColor(CT.fgMuted)

            Divider()

            HStack {
                Button(action: onShare) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(CT.omenGold)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
                Spacer()
                Button(action: onRegenerate) {
                    Label("New style", systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout)
                        .foregroundColor(CT.fgMuted)
                }
            }
        }
        .padding(20)
        .background(CT.surfaceWhite)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        .padding(.horizontal, 20)
    }
}

#Preview {
    OstShareCard(
        descriptor: .init(
            trackIDs: ["1440833568", "1440833569"],
            style: .ambient,
            visitCount: 5,
            shareURL: nil,
            createdAt: Date()
        ),
        onShare: {},
        onRegenerate: {}
    )
}

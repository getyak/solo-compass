import SwiftUI

/// Visual marker for a group of overlapping experience pins. Shows the count
/// and the dominant category's color as a ring.
struct ClusterAnnotationView: View {
    let cluster: MapCluster
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 44, height: 44)
                Circle()
                    .strokeBorder(cluster.dominantCategory.color, lineWidth: 3)
                    .frame(width: 44, height: 44)
                Text("\(cluster.count)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CT.fgPrimary)
            }
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("map.cluster.label", comment: "Cluster of %d experiences"),
            cluster.count
        )))
    }
}

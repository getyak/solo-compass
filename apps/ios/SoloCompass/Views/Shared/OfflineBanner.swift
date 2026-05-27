import SwiftUI

/// Amber pill banner shown in CompassMapView when the app is offline and showing cached data (US-041).
struct OfflineBanner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        GlassmorphismCapsule(
            verticalPadding: 8,
            leading: {
                Image(systemName: "wifi.slash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .scaleEffect(isPulsing ? 1.12 : 0.96)
                    .opacity(isPulsing ? 1.0 : 0.65)
            },
            content: {
                Text(NSLocalizedString("offline.banner", comment: "Offline mode banner"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
            }
        )
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
}

#Preview {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        OfflineBanner()
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

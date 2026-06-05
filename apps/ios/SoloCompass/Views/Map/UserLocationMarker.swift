import SwiftUI

/// The traveler's own dot on the map. Replaces MapKit's built-in
/// `UserAnnotation` blue dot, which renders too small to pick out at a glance —
/// solo travelers kept losing "where am I" against the dense POI markers.
///
/// This is the *center* marker only (a large, high-contrast dot with a white
/// ring and a slow breathing pulse). The surrounding geographic radius circle
/// is drawn separately by a `MapCircle` in the map layer, so the two compose:
/// the marker stays a fixed on-screen size at any zoom, while the circle scales
/// with the map to convey real "nearby" distance.
///
/// Motion respects `accessibilityReduceMotion`: when reduce-motion is on the
/// pulse is suppressed and only the static dot + ring remain.
struct UserLocationMarker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the breathing halo. Toggled on once in `onAppear` so the
    /// `repeatForever` animation keeps running for the marker's lifetime.
    @State private var pulse = false

    /// Diameter of the solid center dot. Comfortably larger than the system
    /// blue dot (~22pt) so it reads at a glance over POI clusters.
    private let coreDiameter: CGFloat = 22

    /// Outer reach of the breathing halo at its largest, relative to the core.
    private let haloScale: CGFloat = 2.4

    var body: some View {
        ZStack {
            // Breathing halo — a soft accent ring that expands and fades. Pure
            // decoration, so it carries no hit target and is hidden from
            // VoiceOver (the dot below owns the accessibility label).
            if !reduceMotion {
                Circle()
                    .fill(Color.accentColor.opacity(0.25))
                    .frame(width: coreDiameter, height: coreDiameter)
                    .scaleEffect(pulse ? haloScale : 1.0)
                    .opacity(pulse ? 0.0 : 0.6)
                    .accessibilityHidden(true)
            }

            // White ring backing — lifts the dot off dark map tiles so it stays
            // legible in both light and dark map styles.
            Circle()
                .fill(.white)
                .frame(width: coreDiameter + 6, height: coreDiameter + 6)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)

            // Solid accent core.
            Circle()
                .fill(Color.accentColor)
                .frame(width: coreDiameter, height: coreDiameter)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(NSLocalizedString(
            "map.userLocation.label",
            comment: "Accessibility label for the traveler's own location marker on the map"
        )))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

#Preview("On light tiles") {
    UserLocationMarker()
        .padding(40)
        .background(Color(white: 0.9))
}

#Preview("On dark tiles") {
    UserLocationMarker()
        .padding(40)
        .background(Color(white: 0.15))
}

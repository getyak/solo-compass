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
        // The white ring backing defines the marker's *layout bounds* — a fixed
        // `coreDiameter + 6`. Everything that animates (the breathing halo) lives
        // in a layout-neutral `.background`, so the reported size never changes.
        //
        // This matters because a SwiftUI `Annotation` re-resolves its anchor
        // point against the content's bounds every frame. If the pulsing halo
        // sat in a `ZStack` (participating in layout), the ZStack would breathe
        // between 22pt and 52.8pt, MapKit would recompute the `.center` anchor
        // against that changing frame, and the whole marker would drift back and
        // forth on screen — decoupled from the real GPS coordinate. Keeping the
        // animated layer out of layout pins the anchor to a constant size.
        Circle()
            .fill(.white)
            .frame(width: coreDiameter + 6, height: coreDiameter + 6)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            // Breathing halo — a soft accent ring that expands and fades. Pure
            // decoration in a layout-neutral background, so it carries no hit
            // target, doesn't grow the marker's measured bounds, and is hidden
            // from VoiceOver (the core dot owns the accessibility label).
            .background {
                if !reduceMotion {
                    Circle()
                        .fill(Color.accentColor.opacity(0.25))
                        .frame(width: coreDiameter, height: coreDiameter)
                        .scaleEffect(pulse ? haloScale : 1.0, anchor: .center)
                        .opacity(pulse ? 0.0 : 0.6)
                        .accessibilityHidden(true)
                }
            }
            // Solid accent core, centered over the white ring.
            .overlay {
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

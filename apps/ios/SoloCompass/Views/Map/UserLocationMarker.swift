import SwiftUI

/// The traveler's own dot on the map. Replaces MapKit's built-in
/// `UserAnnotation` blue dot, which renders too small to pick out at a glance —
/// solo travelers kept losing "where am I" against the dense POI markers.
///
/// This is the *center* marker only: a large, high-contrast accent dot with a
/// white ring. It renders **static** — no perpetual pulse. The earlier design
/// ran a `repeatForever` breathing halo that expanded and faded every 1.6s;
/// against a still map that read as the marker "always flashing", so it was
/// removed. The surrounding geographic radius circle is still drawn separately
/// by a `MapCircle` in the map layer, so the two compose: the marker stays a
/// fixed on-screen size at any zoom, while the circle scales with the map to
/// convey real "nearby" distance.
///
/// The white ring is intentionally kept in the layout bounds while nothing
/// animates, so a SwiftUI `Annotation` resolves its `.center` anchor against a
/// constant size and the marker never drifts off its GPS coordinate.
struct UserLocationMarker: View {
    /// Diameter of the solid center dot. Comfortably larger than the system
    /// blue dot (~22pt) so it reads at a glance over POI clusters.
    private let coreDiameter: CGFloat = 22

    var body: some View {
        // The white ring backing defines the marker's fixed layout bounds
        // (`coreDiameter + 6`). Nothing animates, so the reported size is
        // constant and MapKit's per-frame anchor resolution has nothing to
        // chase — the marker sits still on the real GPS coordinate.
        Circle()
            .fill(.white)
            .frame(width: coreDiameter + 6, height: coreDiameter + 6)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
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

import SwiftUI
import MapKit

/// A compact map with a single draggable/repositionable pin.
/// The caller receives `onCoordinateChanged` whenever the pin moves.
///
/// Tap anywhere on the map to move the pin to that point.
/// The pin itself supports drag-to-reposition via `MapAnnotation`'s
/// built-in drag; we also handle map taps via `MapReader`.
struct MapPinPickerView: View {
    /// The coordinate shown by the pin.
    var coordinate: CLLocationCoordinate2D
    /// Callback fired (on main actor) whenever the pin moves.
    var onCoordinateChanged: (CLLocationCoordinate2D) -> Void

    @State private var cameraPosition: MapCameraPosition

    init(coordinate: CLLocationCoordinate2D, onCoordinateChanged: @escaping (CLLocationCoordinate2D) -> Void) {
        self.coordinate = coordinate
        self.onCoordinateChanged = onCoordinateChanged
        self._cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )))
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                Annotation(
                    NSLocalizedString("locationPicker.map.pin", comment: "Location pin"),
                    coordinate: coordinate
                ) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title)
                        .foregroundStyle(CT.savedRed, .white)
                        .shadow(radius: 4)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .mapControls {
                MapCompass()
            }
            // Tap-to-reposition: convert the tap location to a map coordinate.
            .onTapGesture { screenPoint in
                guard let coord = proxy.convert(screenPoint, from: .local) else { return }
                onCoordinateChanged(coord)
            }
        }
        // Keep the camera centered whenever the pin moves from outside
        // (e.g., text field entry) but don't fight user pan after that.
        .onChange(of: coordinate.latitude) { _, _ in recenterIfFarOff() }
        .onChange(of: coordinate.longitude) { _, _ in recenterIfFarOff() }
    }

    // MARK: - Private

    /// Recenter the camera only when the pin is outside the visible region
    /// (text-field entry, search tap). Avoids fighting user's manual pan.
    private func recenterIfFarOff() {
        guard let region = cameraPosition.region else { return }
        let latDelta = abs(region.center.latitude - coordinate.latitude)
        let lonDelta = abs(region.center.longitude - coordinate.longitude)
        if latDelta > region.span.latitudeDelta * 0.4 || lonDelta > region.span.longitudeDelta * 0.4 {
            withAnimation(.smooth(duration: 0.35)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
        }
    }
}

#Preview {
    MapPinPickerView(
        coordinate: CLLocationCoordinate2D(latitude: 18.7877, longitude: 98.9938),
        onCoordinateChanged: { _ in }
    )
    .frame(height: 300)
}

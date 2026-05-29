import SwiftUI
import CoreLocation
import UIKit

/// Self-contained location block: shows name, address hint, coordinates,
/// and a Navigate button that opens a picker of installed map apps.
struct LocationCard: View {
    let coordinate: CLLocationCoordinate2D
    let displayName: String
    let addressHint: String?

    @State private var isShowingPicker = false
    @State private var didCopy = false
    @Environment(LocationService.self) private var locationService

    private var distanceMeters: Double? {
        let d = locationService.distance(to: coordinate)
        return (d.isFinite && d < .greatestFiniteMagnitude) ? d : nil
    }

    private static let distanceFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .naturalScale
        f.unitStyle = .short
        f.numberFormatter.maximumFractionDigits = 1
        return f
    }()

    private static func formatDistance(_ meters: Double) -> (text: String, symbol: String) {
        if meters < 1500 {
            let minutes = Int((meters / 80.0).rounded(.up))
            let label = minutes < 1
                ? NSLocalizedString("card.distance.walkSub1", comment: "Distance less than 1 min walk")
                : String(format: NSLocalizedString("card.distance.walk", comment: "Distance in walk minutes"), minutes)
            return (label, "figure.walk")
        }
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return (Self.distanceFormatter.string(from: measurement), "location.fill")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let hint = addressHint, !hint.isEmpty {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }

            if let meters = distanceMeters {
                let dl = Self.formatDistance(meters)
                Label(dl.text, systemImage: dl.symbol)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(Color.secondary)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    .accessibilityLabel(String(format: NSLocalizedString("favorites.row.distance.a11y", comment: "Distance away"), dl.text))
            }

            HStack(spacing: 10) {
                // US-010: Primary navigate button with gradient; 44pt HIG minimum
                Button {
                    isShowingPicker = true
                    Haptics.impact(.light)
                } label: {
                    Label(
                        NSLocalizedString("location.navigate", comment: "Open external navigation app"),
                        systemImage: "arrow.triangle.turn.up.right.diamond.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .foregroundStyle(.white)
                }
                .accessibilityLabel(Text(NSLocalizedString("location.navigate", comment: "")))

                // US-010: Ghost copy button — icon only, no fill
                Button {
                    UIPasteboard.general.string = "\(coordinate.latitude), \(coordinate.longitude)"
                    Haptics.notify(.success)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        didCopy = true
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation { didCopy = false }
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(didCopy ? Color.green : Color.secondary)
                        if didCopy {
                            Text(NSLocalizedString("location.copied", comment: "Coordinates copied confirmation"))
                                .font(.caption2)
                                .foregroundStyle(Color.green)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text(didCopy
                    ? NSLocalizedString("location.copied.a11y", comment: "VoiceOver: coordinates were copied")
                    : NSLocalizedString("location.copyCoords", comment: "Copy coordinates to clipboard")
                ))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        .confirmationDialog(
            NSLocalizedString("location.navigate", comment: ""),
            isPresented: $isShowingPicker,
            titleVisibility: .visible
        ) {
            ForEach(NavigationLauncher.availableApps()) { app in
                Button(app.displayName) {
                    NavigationLauncher.open(app: app, coordinate: coordinate, name: displayName)
                }
            }
            Button(NSLocalizedString("action.cancel", comment: "Cancel picker"), role: .cancel) { }
        }
    }
}

#Preview("LocationCard — with distance") {
    let coord = CLLocationCoordinate2D(latitude: 35.7148, longitude: 139.7967)
    let locationService = LocationService()
    locationService.simulate(location: CLLocation(latitude: coord.latitude + 0.004, longitude: coord.longitude))
    return LocationCard(
        coordinate: coord,
        displayName: "浅草寺 Sensō-ji",
        addressHint: "2-3-1 Asakusa, Taito City, Tokyo"
    )
    .padding()
    .environment(locationService)
}

#Preview("LocationCard — no location") {
    LocationCard(
        coordinate: CLLocationCoordinate2D(latitude: 35.7148, longitude: 139.7967),
        displayName: "浅草寺 Sensō-ji",
        addressHint: "2-3-1 Asakusa, Taito City, Tokyo"
    )
    .padding()
    .environment(LocationService())
}

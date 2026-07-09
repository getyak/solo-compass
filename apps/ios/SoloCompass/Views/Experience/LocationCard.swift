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

    private var copyPayload: (text: String, isAddress: Bool) {
        if let hint = addressHint, !hint.isEmpty {
            return (hint, true)
        }
        return (String(format: "%.2f, %.2f", coordinate.latitude, coordinate.longitude), false)
    }

    private func performCopy() {
        UIPasteboard.general.string = copyPayload.text
        Haptics.notify(.success)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            didCopy = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { didCopy = false }
        }
    }

    private var distanceMeters: Double? {
        let d = locationService.distance(to: coordinate)
        return (d.isFinite && d < .greatestFiniteMagnitude) ? d : nil
    }

    /// Tapping Navigate should be a single tap when there's no choice to make.
    /// With one installed maps app we launch it directly; the confirmation
    /// dialog only earns its extra tap when the traveler has more than one app.
    private func navigateTapped() {
        Haptics.impact(.light)
        let apps = NavigationLauncher.availableApps()
        if apps.count <= 1 {
            guard let app = apps.first else { return }
            NavigationLauncher.open(app: app, coordinate: coordinate, name: displayName)
        } else {
            isShowingPicker = true
        }
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
                    .foregroundStyle(CT.savedRed)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let hint = addressHint, !hint.isEmpty {
                        // The address is tap-to-copy, but a bare Text gives no
                        // hint that it's interactive. Pair it with a small copy
                        // glyph (swapping to a green check on success) so the
                        // affordance is discoverable, and give the row a 32pt
                        // tappable height instead of the hairline text bounds.
                        Button { performCopy() } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(hint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                                    .font(.caption2)
                                    .foregroundStyle(didCopy ? CT.verifiedGreen : Color.secondary.opacity(0.6))
                                    .contentTransition(.symbolEffect(.replace))
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: 32, alignment: .topLeading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(hint))
                        .accessibilityValue(didCopy
                            ? Text(NSLocalizedString("location.copiedAddress.a11y", comment: "VoiceOver: address was copied"))
                            : Text(""))
                        .accessibilityHint(Text(NSLocalizedString("location.copyAddress.a11y", comment: "Copy address to clipboard")))
                    } else {
                        // Raw lat/long means nothing to a traveler, so only fall
                        // back to coordinates when there's no address at all —
                        // and at block-level (2dp ≈ ±1km) so we don't surface a
                        // pinpoint location.
                        Text(String(format: "%.2f, %.2f", coordinate.latitude, coordinate.longitude))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
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
                    navigateTapped()
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
                            colors: [CT.accent, CT.accent.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .foregroundStyle(.white)
                }
                .accessibilityLabel(Text(NSLocalizedString("location.navigate", comment: "")))
                .accessibilityHint(Text(NavigationLauncher.availableApps().count > 1
                    ? NSLocalizedString("location.navigate.choose.a11y", comment: "Navigate hint when multiple maps apps installed")
                    : NSLocalizedString("location.navigate.walk.a11y", comment: "Navigate hint when one maps app installed")))

                // US-010: Ghost copy button — icon only, no fill
                Button {
                    performCopy()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(didCopy ? CT.verifiedGreen : Color.secondary)
                        if didCopy {
                            Text(copyPayload.isAddress
                                ? NSLocalizedString("location.copiedAddress", comment: "Address copied confirmation")
                                : NSLocalizedString("location.copied", comment: "Coordinates copied confirmation")
                            )
                            .font(.caption2)
                            .foregroundStyle(CT.verifiedGreen)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text(didCopy
                    ? (copyPayload.isAddress
                        ? NSLocalizedString("location.copiedAddress.a11y", comment: "VoiceOver: address was copied")
                        : NSLocalizedString("location.copied.a11y", comment: "VoiceOver: coordinates were copied"))
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

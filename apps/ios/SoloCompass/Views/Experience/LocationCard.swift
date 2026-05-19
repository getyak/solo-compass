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

            HStack(spacing: 10) {
                Button {
                    isShowingPicker = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label(
                        NSLocalizedString("location.navigate", comment: "Open external navigation app"),
                        systemImage: "location.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor))
                    .foregroundStyle(.white)
                }
                .accessibilityLabel(Text(NSLocalizedString("location.navigate", comment: "")))

                Button {
                    UIPasteboard.general.string = "\(coordinate.latitude), \(coordinate.longitude)"
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel(Text(NSLocalizedString("location.copyCoords", comment: "Copy coordinates to clipboard")))
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

#Preview("LocationCard") {
    LocationCard(
        coordinate: CLLocationCoordinate2D(latitude: 35.7148, longitude: 139.7967),
        displayName: "浅草寺 Sensō-ji",
        addressHint: "2-3-1 Asakusa, Taito City, Tokyo"
    )
    .padding()
}

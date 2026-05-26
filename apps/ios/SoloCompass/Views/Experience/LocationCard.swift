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
                // US-010: Primary navigate button with gradient; 44pt HIG minimum
                Button {
                    isShowingPicker = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
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

#Preview("LocationCard") {
    LocationCard(
        coordinate: CLLocationCoordinate2D(latitude: 35.7148, longitude: 139.7967),
        displayName: "浅草寺 Sensō-ji",
        addressHint: "2-3-1 Asakusa, Taito City, Tokyo"
    )
    .padding()
}

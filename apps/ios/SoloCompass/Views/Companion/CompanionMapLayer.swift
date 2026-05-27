import SwiftUI
import MapKit

/// US-017: Companion "nearby" layer that overlays blurred geohash-6 grid centres
/// on the map. Default off. Toggle must be visible only when FF_COMPANION is on
/// and the user's CompanionProfile visibility is not `.off`.
///
/// Privacy contract: no exact pins are shown — only the centre of a ~600m×600m
/// geohash cell, labelled "~600m away". No user identifiers are rendered.

// MARK: - Model

/// A single nearby-mode discovery hit resolved to its geohash cell centre.
public struct NearbyCell: Identifiable {
    /// Use the geohash string as the identity so duplicates within the same
    /// cell are collapsed to one annotation.
    public var id: String { geohash }
    public let geohash: String
    public let coordinate: CLLocationCoordinate2D

    /// Decode the centre of a geohash-6 cell (precision 6).
    public init?(geohash: String) {
        guard geohash.count == 6 else { return nil }
        guard let coord = GeohashDecoder.centre(of: geohash) else { return nil }
        self.geohash = geohash
        self.coordinate = coord
    }
}

// MARK: - Toggle button (injected into MapControlBar area)

/// Floating pill toggle that enables / disables the companion layer.
/// Placed by `CompassMapView` inside the map ZStack.
public struct CompanionLayerToggle: View {
    @Binding var isLayerOn: Bool
    let presenceActive: Bool
    let companionEnabled: Bool

    private var isDisabled: Bool {
        !companionEnabled || !presenceActive
    }

    public var body: some View {
        Button {
            guard !isDisabled else { return }
            isLayerOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isLayerOn ? "person.2.fill" : "person.2")
                    .font(.caption.weight(.semibold))
                Text(isLayerOn
                     ? NSLocalizedString("companion.layer.on", comment: "Companion layer on")
                     : NSLocalizedString("companion.layer.off", comment: "Companion layer off"))
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(isLayerOn ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isLayerOn ? Color.accentColor : Color(.systemFill))
            )
            .opacity(isDisabled ? 0.45 : 1.0)
        }
        .disabled(isDisabled)
        .accessibilityLabel(Text(isLayerOn
            ? NSLocalizedString("companion.layer.on.a11y", comment: "Companion layer enabled")
            : NSLocalizedString("companion.layer.off.a11y", comment: "Companion layer disabled")))
        .accessibilityHint(isDisabled
            ? Text(NSLocalizedString("companion.layer.hint.inactive", comment: "Enable presence to use companion layer"))
            : Text(NSLocalizedString("companion.layer.hint.active", comment: "Toggle companion nearby view")))
    }
}

// MARK: - Annotation view

/// A blurred annotation marker rendered at a geohash cell centre.
/// Deliberately vague: no name, no avatar, no exact location.
struct NearbyBlurAnnotation: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 44, height: 44)
                .blur(radius: 6)
            Circle()
                .fill(Color.accentColor.opacity(0.55))
                .frame(width: 16, height: 16)
            Text(NSLocalizedString("companion.nearby.label", comment: "~600m away"))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.8)))
                .offset(y: 18)
        }
    }
}

// MARK: - Map annotations helper

/// Returns `MapAnnotation`-style content suitable for insertion into a `Map`
/// content builder. Call from `CompassMapView.mapLayer` when the layer is on.
///
/// Usage inside `Map { ... }`:
/// ```swift
/// if showCompanionLayer {
///     ForEach(nearbyCells) { cell in
///         Annotation("", coordinate: cell.coordinate) {
///             NearbyBlurAnnotation()
///         }
///     }
/// }
/// ```
/// The function itself isn't needed — this comment documents the pattern.

// MARK: - Geohash centre decoder

/// Minimal geohash decoder that returns the centre coordinate of a cell.
enum GeohashDecoder {
    private static let base32 = "0123456789bcdefghjkmnpqrstuvwxyz"

    static func centre(of hash: String) -> CLLocationCoordinate2D? {
        var minLat = -90.0, maxLat = 90.0
        var minLon = -180.0, maxLon = 180.0
        var isEven = true

        for ch in hash.lowercased() {
            guard let idx = base32.firstIndex(of: ch) else { return nil }
            let n = base32.distance(from: base32.startIndex, to: idx)
            for i in stride(from: 4, through: 0, by: -1) {
                let bit = (n >> i) & 1
                if isEven {
                    let mid = (minLon + maxLon) / 2
                    if bit == 1 { minLon = mid } else { maxLon = mid }
                } else {
                    let mid = (minLat + maxLat) / 2
                    if bit == 1 { minLat = mid } else { maxLat = mid }
                }
                isEven.toggle()
            }
        }
        return CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
    }
}

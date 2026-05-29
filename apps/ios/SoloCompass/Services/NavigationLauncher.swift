import UIKit
import MapKit
import CoreLocation

/// External navigation app target. Listed in the user-facing picker.
@MainActor
public enum NavigationApp: String, CaseIterable, Identifiable {
    case appleMaps
    case googleMaps
    case amap

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .appleMaps:  return NSLocalizedString("location.openIn.apple",  comment: "Apple Maps menu item")
        case .googleMaps: return NSLocalizedString("location.openIn.google", comment: "Google Maps menu item")
        case .amap:       return NSLocalizedString("location.openIn.amap",   comment: "Amap (Gaode) menu item")
        }
    }

    /// Probe URL used with `canOpenURL` to detect installation.
    /// Apple Maps returns nil — it is always assumed installed.
    var probeURL: URL? {
        switch self {
        case .appleMaps:  return nil
        case .googleMaps: return URL(string: "comgooglemaps://")
        case .amap:       return URL(string: "iosamap://")
        }
    }
}

/// Builds deep-link URLs and opens the user's preferred navigation app for a coordinate.
///
/// All URL construction is pure and unit-testable. Side-effecting `open` calls go through
/// `UIApplication.shared.open` (or `MKMapItem.openInMaps` for Apple Maps).
@MainActor
public enum NavigationLauncher {

    /// Apps available on the current device, in canonical display order.
    /// `canOpen` is injectable for unit tests.
    public static func availableApps(
        canOpen: (URL) -> Bool = { UIApplication.shared.canOpenURL($0) }
    ) -> [NavigationApp] {
        NavigationApp.allCases.filter { app in
            guard let url = app.probeURL else { return true }
            return canOpen(url)
        }
    }

    /// Deep-link URL for the given app. Returns nil for Apple Maps (use `open(app:...)` instead,
    /// which dispatches to `MKMapItem.openInMaps`).
    public static func url(
        for app: NavigationApp,
        coordinate: CLLocationCoordinate2D,
        name: String?
    ) -> URL? {
        let encodedName = (name ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let lat = coordinate.latitude
        let lon = coordinate.longitude

        switch app {
        case .appleMaps:
            return nil
        case .googleMaps:
            return URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&q=\(encodedName)&directionsmode=walking")
        case .amap:
            // dev=0 declares the coordinate is GPS (WGS-84); Amap converts to GCJ-02 internally.
            // t=2 selects walking mode.
            return URL(string: "iosamap://path?sourceApplication=SoloCompass&dlat=\(lat)&dlon=\(lon)&dname=\(encodedName)&dev=0&t=2")
        }
    }

    /// Launches walking directions to an experience in the traveler's chosen maps app.
    public static func open(
        app: NavigationApp,
        coordinate: CLLocationCoordinate2D,
        name: String?
    ) {
        if app == .appleMaps {
            let placemark = MKPlacemark(coordinate: coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
            return
        }
        guard let url = url(for: app, coordinate: coordinate, name: name) else { return }
        UIApplication.shared.open(url)
    }
}

import Foundation
import CoreLocation
import MapKit
import Observation

/// Transient UI state for LocationPickerSheet.
/// Lifetime: created when the sheet opens, discarded on dismiss.
@MainActor
@Observable
final class LocationPickerState {
    enum Tab: String, CaseIterable {
        case cities, search, map
        var label: String {
            switch self {
            case .cities: return NSLocalizedString("locationPicker.tab.cities", comment: "Cities tab")
            case .search: return NSLocalizedString("locationPicker.tab.search", comment: "Search tab")
            case .map:    return NSLocalizedString("locationPicker.tab.map",    comment: "Map tab")
            }
        }
    }

    var selectedTab: Tab = .cities

    // MARK: Cities tab
    var citySearchQuery: String = ""

    // MARK: Search tab
    var searchQuery: String = ""
    var searchResults: [MKMapItem] = []
    var isSearching: Bool = false
    var searchError: String?

    // MARK: Map tab
    var pinCoordinate: CLLocationCoordinate2D
    var manualLatText: String = ""
    var manualLonText: String = ""
    var resolvedCityName: String?
    var isResolving: Bool = false

    init(initialCoordinate: CLLocationCoordinate2D) {
        self.pinCoordinate = initialCoordinate
        self.manualLatText = String(format: "%.4f", initialCoordinate.latitude)
        self.manualLonText = String(format: "%.4f", initialCoordinate.longitude)
    }

    /// Update the pin coordinate and sync the text fields.
    func updatePin(to coordinate: CLLocationCoordinate2D) {
        pinCoordinate = coordinate
        manualLatText = String(format: "%.4f", coordinate.latitude)
        manualLonText = String(format: "%.4f", coordinate.longitude)
        resolvedCityName = nil
    }

    /// Parse text fields → coordinate. Returns nil if either field is invalid.
    func parsedCoordinate() -> CLLocationCoordinate2D? {
        guard let lat = Double(manualLatText),
              let lon = Double(manualLonText),
              lat >= -90, lat <= 90,
              lon >= -180, lon <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

import Foundation
import CoreLocation

/// A user-created city persisted across launches via CustomCityStore.
struct SavedCity: Codable, Identifiable, Hashable {
    let id: String          // "custom_{uuid}"
    var name: String
    var latitude: Double
    var longitude: Double
    var countryCode: String?
    var dateAdded: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

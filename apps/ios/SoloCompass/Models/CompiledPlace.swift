import Foundation
import CoreLocation
import MapKit

// MARK: - SourceTag

public enum SourceTag: String, Codable, Hashable {
    case osm
    case foursquare
    case mapkit
    case web
}

// MARK: - TaggedField

public struct TaggedField<T: Codable & Hashable>: Codable, Hashable {
    public let value: T
    public let source: SourceTag
    public let accessedAt: Date

    public init(value: T, source: SourceTag, accessedAt: Date = Date()) {
        self.value = value
        self.source = source
        self.accessedAt = accessedAt
    }
}

// MARK: - CompiledPlace

/// A cross-source merged record produced before AI synthesis. Each field
/// carries its originating source tag so provenance survives into the
/// synthesized Experience and its InformationSource list.
public struct CompiledPlace: Hashable {
    public let coordinate: CLLocationCoordinate2D
    public let name: TaggedField<String>
    public let rating: TaggedField<Double>?
    public let openingHours: TaggedField<String>?
    public let priceLevel: TaggedField<Double>?
    public let website: TaggedField<String>?
    public let phone: TaggedField<String>?
    public let address: TaggedField<String>?
    /// Number of distinct sources that contributed at least one field.
    public let sourcesCount: Int

    public init(
        coordinate: CLLocationCoordinate2D,
        name: TaggedField<String>,
        rating: TaggedField<Double>? = nil,
        openingHours: TaggedField<String>? = nil,
        priceLevel: TaggedField<Double>? = nil,
        website: TaggedField<String>? = nil,
        phone: TaggedField<String>? = nil,
        address: TaggedField<String>? = nil,
        sourcesCount: Int
    ) {
        self.coordinate = coordinate
        self.name = name
        self.rating = rating
        self.openingHours = openingHours
        self.priceLevel = priceLevel
        self.website = website
        self.phone = phone
        self.address = address
        self.sourcesCount = sourcesCount
    }

    // MARK: Hashable

    public static func == (lhs: CompiledPlace, rhs: CompiledPlace) -> Bool {
        lhs.name.value == rhs.name.value
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.sourcesCount == rhs.sourcesCount
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name.value)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(sourcesCount)
    }
}

// MARK: - POI tag conversion

extension CompiledPlace {
    /// Convert this compiled place's fields to a flat `[String: String]` tag
    /// dictionary compatible with `OverpassService.POI.tags`. This feeds the
    /// existing AI synthesis prompt builder without change.
    public func toPoiTags() -> [String: String] {
        var tags: [String: String] = ["name": name.value, "source": name.source.rawValue]
        if let r = rating { tags["fsq_rating"] = String(r.value) }
        if let h = openingHours { tags["opening_hours"] = h.value }
        if let p = priceLevel { tags["fsq_price"] = String(p.value) }
        if let w = website { tags["website"] = w.value }
        if let ph = phone { tags["phone"] = ph.value }
        if let a = address { tags["addr"] = a.value }
        return tags
    }
}

// MARK: - Confidence mapping

extension CompiledPlace {
    /// Map a CompiledPlace's sourcesCount to an integer confidence level
    /// compatible with `Confidence.level` (0–5).
    /// Single source: 1 (low). 2 sources: 2. 3+ sources: 3 (medium-high).
    /// This is applied in post-synthesis to bump the synthesized Experience.
    public static func confidenceLevel(for place: CompiledPlace) -> Int {
        switch place.sourcesCount {
        case 0:       return 0
        case 1:       return 1
        case 2:       return 2
        default:      return 3
        }
    }
}

// MARK: - Cross-source merge

extension CompiledPlace {
    /// Trust order for coordinate / name: OSM > anything else.
    /// Trust order for rating / hours / price: Foursquare > MapKit.
    /// Trust order for address: MapKit structured > reverse-geocode (OSM addr tag).
    ///
    /// A field is taken from a lower-priority source only when the
    /// higher-priority source does not provide it. `sourcesCount` counts the
    /// number of distinct source types that contributed at least one field.
    public static func merge(
        pois: [OverpassService.POI],
        venues: [FoursquareService.LiteVenue],
        mapItems: [MKMapItem]
    ) -> CompiledPlace? {
        // Prefer OSM POI for coordinate and name.
        let osmPoi = pois.first { $0.tags["source"] == nil || $0.tags["source"] == "osm" }
            ?? pois.first
        let fsqVenue = venues.first
        let mapItem = mapItems.first

        guard osmPoi != nil || fsqVenue != nil || mapItem != nil else { return nil }
        let now = Date()

        // Coordinate: OSM > MapKit > Foursquare.
        let coordinate: CLLocationCoordinate2D
        if let p = osmPoi {
            coordinate = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
        } else if let m = mapItem {
            coordinate = m.placemark.coordinate
        } else if let v = fsqVenue {
            coordinate = CLLocationCoordinate2D(latitude: v.lat, longitude: v.lon)
        } else {
            return nil
        }

        // Name: OSM > MapKit > Foursquare.
        let nameValue: String
        let nameSource: SourceTag
        if let p = osmPoi, !p.name.isEmpty {
            nameValue = p.name; nameSource = .osm
        } else if let m = mapItem, let n = m.name, !n.isEmpty {
            nameValue = n; nameSource = .mapkit
        } else if let v = fsqVenue, !v.name.isEmpty {
            nameValue = v.name; nameSource = .foursquare
        } else {
            return nil
        }
        let nameField = TaggedField(value: nameValue, source: nameSource, accessedAt: now)

        // Rating / hours / price: Foursquare > MapKit (MapKit doesn't expose
        // rating or hours in the public API, so this is effectively Foursquare-only).
        let ratingField: TaggedField<Double>? = fsqVenue.flatMap { v in
            v.rating.map { TaggedField(value: $0, source: .foursquare, accessedAt: now) }
        }

        let hoursField: TaggedField<String>? = fsqVenue.flatMap { v in
            v.hours.map { TaggedField(value: $0, source: .foursquare, accessedAt: now) }
        } ?? osmPoi.flatMap { p in
            p.tags["opening_hours"].map { TaggedField(value: $0, source: .osm, accessedAt: now) }
        }

        let priceField: TaggedField<Double>? = fsqVenue.flatMap { v in
            v.price.map { TaggedField(value: Double($0), source: .foursquare, accessedAt: now) }
        }

        // Website / phone: any source, prefer OSM then Foursquare then MapKit.
        let websiteValue = osmPoi?.tags["website"] ?? fsqVenue?.website
            ?? mapItem?.url?.absoluteString
        let websiteField = websiteValue.map { TaggedField(value: $0, source: .osm, accessedAt: now) }

        let phoneValue = osmPoi?.tags["phone"] ?? fsqVenue?.phone
            ?? mapItem?.phoneNumber
        let phoneField = phoneValue.map { TaggedField(value: $0, source: .osm, accessedAt: now) }

        // Address: MapKit structured > OSM addr tag.
        let addressField: TaggedField<String>?
        if let m = mapItem, let thoroughfare = m.placemark.thoroughfare {
            let full = [m.placemark.subThoroughfare, thoroughfare]
                .compactMap { $0 }.joined(separator: " ")
            addressField = TaggedField(
                value: full.isEmpty ? thoroughfare : full,
                source: .mapkit,
                accessedAt: now
            )
        } else if let addr = osmPoi?.tags["addr"] {
            addressField = TaggedField(value: addr, source: .osm, accessedAt: now)
        } else {
            addressField = nil
        }

        // Count distinct contributing source types.
        var sources = Set<SourceTag>()
        sources.insert(nameSource)
        if let r = ratingField { sources.insert(r.source) }
        if let h = hoursField { sources.insert(h.source) }
        if let p = priceField { sources.insert(p.source) }
        if let w = websiteField { sources.insert(w.source) }
        if let ph = phoneField { sources.insert(ph.source) }
        if let a = addressField { sources.insert(a.source) }

        return CompiledPlace(
            coordinate: coordinate,
            name: nameField,
            rating: ratingField,
            openingHours: hoursField,
            priceLevel: priceField,
            website: websiteField,
            phone: phoneField,
            address: addressField,
            sourcesCount: sources.count
        )
    }
}

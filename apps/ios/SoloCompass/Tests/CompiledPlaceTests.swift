import XCTest
import CoreLocation
import MapKit
@testable import SoloCompass

// MARK: - US-012 CompiledPlace model

final class CompiledPlaceTests: XCTestCase {

    // MARK: - US-012: field-level source tags preserved through toPoiTags()

    func testTaggedFieldSourceTagPreservedInPoiTags() {
        let now = Date()
        let place = CompiledPlace(
            coordinate: CLLocationCoordinate2D(latitude: 21.0, longitude: 105.8),
            name: TaggedField(value: "Giang Cafe", source: .osm, accessedAt: now),
            rating: TaggedField(value: 8.5, source: .foursquare, accessedAt: now),
            openingHours: TaggedField(value: "Mon-Fri 8am-6pm", source: .foursquare, accessedAt: now),
            priceLevel: TaggedField(value: 2.0, source: .foursquare, accessedAt: now),
            website: TaggedField(value: "https://example.com", source: .osm, accessedAt: now),
            phone: TaggedField(value: "+84123456789", source: .osm, accessedAt: now),
            address: TaggedField(value: "39 Nguyen Huu Huan", source: .mapkit, accessedAt: now),
            sourcesCount: 3
        )

        let tags = place.toPoiTags()

        XCTAssertEqual(tags["name"], "Giang Cafe")
        XCTAssertEqual(tags["fsq_rating"], "8.5")
        XCTAssertEqual(tags["opening_hours"], "Mon-Fri 8am-6pm")
        XCTAssertEqual(tags["fsq_price"], "2.0")
        XCTAssertEqual(tags["website"], "https://example.com")
        XCTAssertEqual(tags["phone"], "+84123456789")
        XCTAssertEqual(tags["addr"], "39 Nguyen Huu Huan")
        XCTAssertEqual(tags["source"], "osm", "name source tag preserved")
    }

    func testPoiTagsNilFieldsOmitted() {
        let place = CompiledPlace(
            coordinate: CLLocationCoordinate2D(latitude: 21.0, longitude: 105.8),
            name: TaggedField(value: "Minimal Place", source: .osm),
            sourcesCount: 1
        )
        let tags = place.toPoiTags()
        XCTAssertEqual(tags["name"], "Minimal Place")
        XCTAssertNil(tags["fsq_rating"])
        XCTAssertNil(tags["opening_hours"])
        XCTAssertNil(tags["fsq_price"])
        XCTAssertNil(tags["website"])
        XCTAssertNil(tags["phone"])
        XCTAssertNil(tags["addr"])
    }

    // MARK: - US-013: cross-source merge conflict resolution

    func testMergePreferOsmForCoordinateAndName() {
        let osmPoi = OverpassService.POI(
            osmId: 1001,
            name: "OSM Cafe",
            nameEn: nil,
            lat: 21.034,
            lon: 105.852,
            tags: ["amenity": "cafe", "name": "OSM Cafe"]
        )
        let fsqVenue = FoursquareService.LiteVenue(
            fsqId: "fsq123",
            name: "FSQ Cafe",
            lat: 21.034,
            lon: 105.852,
            rating: 8.5,
            price: 2,
            hours: "Mon-Fri 8am-6pm",
            website: nil,
            phone: nil
        )
        let place = CompiledPlace.merge(pois: [osmPoi], venues: [fsqVenue], mapItems: [])
        XCTAssertNotNil(place)
        XCTAssertEqual(place?.name.value, "OSM Cafe", "OSM name takes priority")
        XCTAssertEqual(place?.name.source, .osm)
        XCTAssertEqual(place?.coordinate.latitude, 21.034, accuracy: 0.0001)
    }

    func testMergePrefersFoursquareForRatingHoursPrice() {
        let osmPoi = OverpassService.POI(
            osmId: 1002,
            name: "Place",
            nameEn: nil,
            lat: 21.0,
            lon: 105.8,
            tags: ["amenity": "cafe", "opening_hours": "OSM hours"]
        )
        let fsqVenue = FoursquareService.LiteVenue(
            fsqId: "fsq456",
            name: "Place",
            lat: 21.0,
            lon: 105.8,
            rating: 9.0,
            price: 3,
            hours: "FSQ hours",
            website: nil,
            phone: nil
        )
        let place = CompiledPlace.merge(pois: [osmPoi], venues: [fsqVenue], mapItems: [])
        XCTAssertEqual(place?.rating?.value, 9.0, accuracy: 0.01)
        XCTAssertEqual(place?.rating?.source, .foursquare)
        XCTAssertEqual(place?.openingHours?.value, "FSQ hours", "Foursquare hours win over OSM")
        XCTAssertEqual(place?.openingHours?.source, .foursquare)
        XCTAssertEqual(place?.priceLevel?.value, 3.0, accuracy: 0.01)
    }

    func testMergeMissingFoursquareFallsBackToOsmForHours() {
        let osmPoi = OverpassService.POI(
            osmId: 1003,
            name: "Place",
            nameEn: nil,
            lat: 21.0,
            lon: 105.8,
            tags: ["amenity": "cafe", "opening_hours": "OSM only hours"]
        )
        let place = CompiledPlace.merge(pois: [osmPoi], venues: [], mapItems: [])
        XCTAssertEqual(place?.openingHours?.value, "OSM only hours")
        XCTAssertEqual(place?.openingHours?.source, .osm)
        XCTAssertNil(place?.rating, "no Foursquare → rating stays nil")
    }

    func testMergeSourcesCountReflectsDistinctContributors() {
        let osmPoi = OverpassService.POI(
            osmId: 1004,
            name: "Multi-source Place",
            nameEn: nil,
            lat: 21.0,
            lon: 105.8,
            tags: ["amenity": "restaurant", "name": "Multi-source Place"]
        )
        let fsqVenue = FoursquareService.LiteVenue(
            fsqId: "fsq789",
            name: "Multi-source Place",
            lat: 21.0,
            lon: 105.8,
            rating: 7.5,
            price: 2,
            hours: "8am-10pm",
            website: nil,
            phone: nil
        )
        let place = CompiledPlace.merge(pois: [osmPoi], venues: [fsqVenue], mapItems: [])
        XCTAssertNotNil(place)
        // Name is from OSM, rating/hours/price from Foursquare → 2 distinct sources.
        XCTAssertGreaterThanOrEqual(place!.sourcesCount, 2, "OSM + Foursquare = at least 2 sources")
    }

    func testMergeReturnsNilWhenAllSourcesEmpty() {
        let place = CompiledPlace.merge(pois: [], venues: [], mapItems: [])
        XCTAssertNil(place)
    }

    func testMergeSingleOsmSourceCountIsOne() {
        let osmPoi = OverpassService.POI(
            osmId: 1005,
            name: "Solo OSM",
            nameEn: nil,
            lat: 10.0,
            lon: 20.0,
            tags: ["amenity": "cafe"]
        )
        let place = CompiledPlace.merge(pois: [osmPoi], venues: [], mapItems: [])
        XCTAssertEqual(place?.sourcesCount, 1)
    }

    // MARK: - US-014: multi-source confidence bump

    func testSingleSourceConfidenceLevelIsLower() {
        let single = CompiledPlace(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            name: TaggedField(value: "Single", source: .osm),
            sourcesCount: 1
        )
        let multi = CompiledPlace(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            name: TaggedField(value: "Multi", source: .osm),
            rating: TaggedField(value: 8.0, source: .foursquare),
            sourcesCount: 2
        )
        let singleLevel = CompiledPlace.confidenceLevel(for: single)
        let multiLevel = CompiledPlace.confidenceLevel(for: multi)
        XCTAssertGreaterThan(multiLevel, singleLevel,
                             "≥2 sources must produce a higher confidence level than 1 source")
    }

    func testThreeSourcesReturnsHigherConfidenceThanTwo() {
        let two = CompiledPlace(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            name: TaggedField(value: "Two", source: .osm),
            sourcesCount: 2
        )
        let three = CompiledPlace(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            name: TaggedField(value: "Three", source: .osm),
            sourcesCount: 3
        )
        XCTAssertGreaterThanOrEqual(
            CompiledPlace.confidenceLevel(for: three),
            CompiledPlace.confidenceLevel(for: two)
        )
    }
}

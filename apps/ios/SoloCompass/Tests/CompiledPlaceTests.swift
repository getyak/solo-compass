import XCTest
import CoreLocation
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

    func testMergePreferOsmForCoordinateAndName() throws {
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
        let unwrappedPlace = try XCTUnwrap(place)
        XCTAssertEqual(unwrappedPlace.coordinate.latitude, 21.034, accuracy: 0.0001)
    }

    func testMergePrefersFoursquareForRatingHoursPrice() throws {
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
        let place2 = try XCTUnwrap(place)
        XCTAssertEqual(try XCTUnwrap(place2.rating?.value), 9.0, accuracy: 0.01)
        XCTAssertEqual(place?.rating?.source, .foursquare)
        XCTAssertEqual(place?.openingHours?.value, "FSQ hours", "Foursquare hours win over OSM")
        XCTAssertEqual(place?.openingHours?.source, .foursquare)
        XCTAssertEqual(try XCTUnwrap(place2.priceLevel?.value), 3.0, accuracy: 0.01)
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

    // MARK: - US-013: additional merge edge cases

    func testMergeOsmOnlyNoFoursquareNoMapKit() {
        let osmPoi = OverpassService.POI(
            osmId: 2001,
            name: "OSM Only",
            nameEn: nil,
            lat: 13.0,
            lon: 100.0,
            tags: ["amenity": "cafe", "website": "https://osm-site.com", "phone": "+66-999"]
        )
        let place = CompiledPlace.merge(pois: [osmPoi], venues: [], mapItems: [])
        XCTAssertNotNil(place)
        XCTAssertEqual(place?.name.source, .osm)
        XCTAssertEqual(place?.website?.value, "https://osm-site.com")
        XCTAssertEqual(place?.phone?.value, "+66-999")
        XCTAssertEqual(place?.sourcesCount, 1)
    }

    func testMergeFoursquareRatingAbsentWhenNoVenue() {
        let osmPoi = OverpassService.POI(
            osmId: 2002,
            name: "No Rating",
            nameEn: nil,
            lat: 13.0,
            lon: 100.0,
            tags: [:]
        )
        let place = CompiledPlace.merge(pois: [osmPoi], venues: [], mapItems: [])
        XCTAssertNil(place?.rating, "rating must be nil when no Foursquare venue supplied")
        XCTAssertNil(place?.priceLevel, "price must be nil when no Foursquare venue supplied")
    }

    func testMergeFoursquareOnlyFallback() {
        let fsqVenue = FoursquareService.LiteVenue(
            fsqId: "fsq-only",
            name: "FSQ Only Place",
            lat: 2.0,
            lon: 103.0,
            rating: 6.0,
            price: 1,
            hours: "All day",
            website: "https://fsq.com",
            phone: nil
        )
        let place = CompiledPlace.merge(pois: [], venues: [fsqVenue], mapItems: [])
        XCTAssertNotNil(place)
        XCTAssertEqual(place?.name.value, "FSQ Only Place")
        XCTAssertEqual(place?.name.source, .foursquare)
        XCTAssertEqual(place?.rating?.source, .foursquare)
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

    func testApplyMultiSourceAttributionBumpsConfidenceAndSources() throws {
        let base = try XCTUnwrap(ExperienceService.hardcodedSeed.first)
        let singleSourceExp = Experience(
            id: "us014-test",
            title: base.title,
            oneLiner: base.oneLiner,
            whyItMatters: base.whyItMatters,
            category: base.category,
            location: base.location,
            bestTimes: base.bestTimes,
            durationMinutes: base.durationMinutes,
            howTo: base.howTo,
            realInconveniences: base.realInconveniences,
            soloScore: SoloScore(overall: 7.5, breakdown: base.soloScore.breakdown, basedOnCount: 1),
            sources: [
                InformationSource(
                    type: .user,
                    url: nil,
                    attribution: "© OpenStreetMap contributors + AI",
                    verifiedAt: Date()
                )
            ],
            confidence: Confidence(
                level: 1,
                lastVerifiedAt: Date(),
                reason: "single source",
                signals: .init(aiScrapeAgeDays: 0, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
            ),
            nearbyExperienceIds: [],
            stats: base.stats,
            status: base.status,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt
        )

        let multiSourcePlace = CompiledPlace(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            name: TaggedField(value: "Multi", source: .osm),
            rating: TaggedField(value: 8.5, source: .foursquare),
            sourcesCount: 2
        )

        let enriched = AIService.applyMultiSourceAttribution(
            to: singleSourceExp,
            compiledPlace: multiSourcePlace
        )

        XCTAssertGreaterThan(enriched.confidence.level, singleSourceExp.confidence.level,
                             "Confidence level must be bumped for multi-source place")
        XCTAssertGreaterThan(enriched.soloScore.basedOnCount, 1,
                             "basedOnCount must be bumped to reflect multi-source count")
        XCTAssertGreaterThan(enriched.sources.count, singleSourceExp.sources.count,
                             "sources list must include additional per-source entries")
    }

    func testApplyMultiSourceAttributionIsNoOpForSingleSource() throws {
        let base = try XCTUnwrap(ExperienceService.hardcodedSeed.first)
        let exp = Experience(
            id: "us014-single",
            title: base.title,
            oneLiner: base.oneLiner,
            whyItMatters: base.whyItMatters,
            category: base.category,
            location: base.location,
            bestTimes: base.bestTimes,
            durationMinutes: base.durationMinutes,
            howTo: base.howTo,
            realInconveniences: base.realInconveniences,
            soloScore: base.soloScore,
            sources: base.sources,
            confidence: base.confidence,
            nearbyExperienceIds: [],
            stats: base.stats,
            status: base.status,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt
        )

        let singleSourcePlace = CompiledPlace(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            name: TaggedField(value: "Single", source: .osm),
            sourcesCount: 1
        )

        let result = AIService.applyMultiSourceAttribution(to: exp, compiledPlace: singleSourcePlace)
        XCTAssertEqual(result.confidence.level, exp.confidence.level,
                       "No-op for single-source: confidence must not change")
        XCTAssertEqual(result.soloScore.basedOnCount, exp.soloScore.basedOnCount,
                       "No-op for single-source: basedOnCount must not change")
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

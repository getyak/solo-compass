import XCTest
import CoreLocation
@testable import SoloCompass

/// Unit coverage for the Amap (AutoNavi) mainland-China POI source. The network
/// call itself is not exercised here (no live key in CI); instead we lock down
/// the pure, deterministic edges that carry the integration's correctness:
///   1. Category → Amap typecode mapping (every `ExperienceCategory` case).
///   2. URL building: GCJ-02 center formatting, radius / page_size clamping,
///      and the fixed query contract Amap expects.
///   3. POI mapping: GCJ-02 → WGS84 conversion, tag projection, and the
///      defensive drops (missing name / coordinate, the literal `"[]"` phone).
///   4. Stable id: source-distinct high bit and determinism.
///   5. Empty-key gating: `fetchPOIs` throws `missingKey` so the caller can
///      fall back to Overpass (ADR §3.3).
@MainActor
final class AmapPOIServiceTests: XCTestCase {

    // Shenzhen Futian CBD (WGS84) — squarely on the mainland Amap branch.
    private let shenzhen = CLLocationCoordinate2D(latitude: 22.5431, longitude: 114.0579)

    // MARK: - Category → typecode

    func testEveryCategoryMapsExceptHidden() {
        // `hidden` is intentionally a broad search (nil types); every other
        // category must resolve to a non-empty Amap typecode string.
        for category in ExperienceCategory.allCases {
            let types = AmapPOIService.amapTypes(for: category)
            if category == .hidden {
                XCTAssertNil(types, "hidden should issue a broad (untyped) search")
            } else {
                XCTAssertNotNil(types, "\(category) must map to an Amap typecode")
                XCTAssertFalse(types!.isEmpty)
            }
        }
    }

    func testCoffeeMapsToCafeTypecode() {
        XCTAssertEqual(AmapPOIService.amapTypes(for: .coffee), "050500")
    }

    // MARK: - URL building

    func testBuildURLCarriesTheAmapContract() throws {
        let gcj = CoordinateConverter.wgs84ToGcj02(shenzhen)
        let url = try XCTUnwrap(AmapPOIService.buildURL(
            key: "TEST_KEY",
            gcjCenter: gcj,
            radiusMeters: 3000,
            category: .coffee,
            pageSize: 25
        ))
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.host, "restapi.amap.com")
        XCTAssertEqual(comps.path, "/v5/place/around")
        let items = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["key"], "TEST_KEY")
        XCTAssertEqual(items["radius"], "3000")
        XCTAssertEqual(items["page_size"], "25")
        XCTAssertEqual(items["sortrule"], "distance")
        XCTAssertEqual(items["types"], "050500")
        // location must be "lon,lat" (GeoJSON order) at 6 decimals.
        let loc = try XCTUnwrap(items["location"] ?? nil)
        let parts = loc.split(separator: ",")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(Double(parts[0])!, gcj.longitude, accuracy: 1e-5)
        XCTAssertEqual(Double(parts[1])!, gcj.latitude, accuracy: 1e-5)
    }

    func testBuildURLClampsRadiusAndPageSize() throws {
        let url = try XCTUnwrap(AmapPOIService.buildURL(
            key: "K",
            gcjCenter: shenzhen,
            radiusMeters: 999_999, // over the 50 km cap
            category: nil,         // no `types` filter
            pageSize: 100          // over the 25 cap
        ))
        let items = Dictionary(uniqueKeysWithValues:
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["radius"], "50000")
        XCTAssertEqual(items["page_size"], "25")
        XCTAssertNil(items["types"] ?? nil, "nil category must omit the types filter")
    }

    // MARK: - typecode → OSM tag

    func testTypecodeToOSMTag() {
        XCTAssertEqual(AmapPOIService.osmTag(forTypecode: "050500")?.value, "cafe")
        // 酒吧 (050118) must resolve to bar, not the 05-wildcard restaurant.
        XCTAssertEqual(AmapPOIService.osmTag(forTypecode: "050118")?.value, "bar")
        // Other 05 dining codes still fall through to restaurant.
        XCTAssertEqual(AmapPOIService.osmTag(forTypecode: "050100")?.value, "restaurant")
        XCTAssertEqual(AmapPOIService.osmTag(forTypecode: "110000")?.value, "attraction")
        XCTAssertEqual(AmapPOIService.osmTag(forTypecode: "140600")?.value, "museum")
        XCTAssertNil(AmapPOIService.osmTag(forTypecode: "990000"), "unknown prefix → nil")
    }

    // MARK: - POI mapping

    func testPOIMappingConvertsGCJToWGSAndProjectsTags() throws {
        // Build a GCJ-02 location the way Amap returns it, from a known WGS84
        // origin, so we can assert the round-trip lands back near the origin.
        let gcj = CoordinateConverter.wgs84ToGcj02(shenzhen)
        let amap = AmapPOIService.AmapPOI(
            id: "B0FFABCDEF",
            name: "测试咖啡馆",
            location: String(format: "%.6f,%.6f", gcj.longitude, gcj.latitude),
            typecode: "050500",
            address: "福田区某路1号",
            tel: "0755-12345678",
            business: .init(opentimeToday: "09:00-21:00", rating: "4.6")
        )
        let poi = try XCTUnwrap(AmapPOIService.poi(from: amap))

        // Converted coordinate must be back in WGS84, near the original origin.
        let backLoc = CLLocation(latitude: poi.lat, longitude: poi.lon)
        let originLoc = CLLocation(latitude: shenzhen.latitude, longitude: shenzhen.longitude)
        XCTAssertLessThan(originLoc.distance(from: backLoc), 1.0)

        XCTAssertEqual(poi.name, "测试咖啡馆")
        XCTAssertEqual(poi.tags["source"], "amap")
        XCTAssertEqual(poi.tags["amenity"], "cafe")
        // Compliance (ADR §3.2): Amap's raw structured fields must NOT be
        // projected into tags, because the downstream Experience is persisted to
        // SwiftData and Amap's ToS forbids storing/redistributing its raw data.
        // Only name + source marker + category bucket survive.
        XCTAssertNil(poi.tags["addr"], "raw address must not be persisted")
        XCTAssertNil(poi.tags["phone"], "raw phone must not be persisted")
        XCTAssertNil(poi.tags["opening_hours"], "raw hours must not be persisted")
        XCTAssertNil(poi.tags["amap_rating"], "raw rating must not be persisted")
    }

    func testPOIMappingDropsMissingNameOrCoordinate() {
        let noName = AmapPOIService.AmapPOI(
            id: "1", name: nil, location: "114.06,22.54",
            typecode: nil, address: nil, tel: nil, business: nil
        )
        XCTAssertNil(AmapPOIService.poi(from: noName))

        let noLoc = AmapPOIService.AmapPOI(
            id: "1", name: "X", location: nil,
            typecode: nil, address: nil, tel: nil, business: nil
        )
        XCTAssertNil(AmapPOIService.poi(from: noLoc))
    }

    func testPOIMappingTreatsEmptyArrayPhoneAsAbsent() throws {
        // Amap returns the literal "[]" for a POI with no phone; it must not
        // land as a bogus `phone` tag.
        let amap = AmapPOIService.AmapPOI(
            id: "1", name: "X", location: "114.06,22.54",
            typecode: nil, address: nil, tel: "[]", business: nil
        )
        let poi = try XCTUnwrap(AmapPOIService.poi(from: amap))
        XCTAssertNil(poi.tags["phone"])
    }

    // MARK: - Stable id

    func testStableIdIsDeterministicAndSourceTagged() {
        let a = AmapPOIService.stableInt64Id(amapId: "B0ABC", name: "X", coordinate: shenzhen)
        let b = AmapPOIService.stableInt64Id(amapId: "B0ABC", name: "X", coordinate: shenzhen)
        XCTAssertEqual(a, b, "same input → same id")
        // The implementation sets marker bit 60 (`| 0x1000…`) to distinguish
        // Amap ids from OSM (low range), MapKit (bit 61), and Foursquare
        // (bit 62) — assert that bit, not the whole nibble (bits 61/62 carry
        // hash entropy). Bit 63 (sign) is always cleared, so the id is positive.
        let bits = UInt64(bitPattern: a)
        XCTAssertEqual(bits & 0x1000_0000_0000_0000, 0x1000_0000_0000_0000, "Amap marker bit 60 must be set")
        XCTAssertEqual(bits & 0x8000_0000_0000_0000, 0, "sign bit must be clear (positive id)")
        XCTAssertGreaterThan(a, 0)

        let differentId = AmapPOIService.stableInt64Id(amapId: "B0XYZ", name: "X", coordinate: shenzhen)
        XCTAssertNotEqual(a, differentId, "different Amap id → different stable id")
    }

    // MARK: - Empty-key gating

    func testFetchThrowsMissingKeyWhenKeyEmpty() async {
        let service = AmapPOIService(keyProvider: { "" })
        do {
            _ = try await service.fetchPOIs(near: shenzhen)
            XCTFail("expected missingKey to throw")
        } catch let error as AmapPOIService.AmapError {
            guard case .missingKey = error else {
                return XCTFail("expected .missingKey, got \(error)")
            }
        } catch {
            XCTFail("expected AmapError.missingKey, got \(error)")
        }
    }

    // MARK: - Wire-format contract (CI-safe replacement for AmapLiveIntegrationTests
    // which XCTSkipIfs without a real key). Locks down the JSON contract so a
    // silent decoder regression (e.g. amap returning int `1` instead of `"1"`)
    // trips here instead of on device with no diagnostic.

    func testFlexibleDecoderAcceptsStringStatus() throws {
        let json = #"{"status":"1","info":"OK","infocode":"10000","pois":[{"id":"B1","name":"Café","location":"114.0579,22.5431","typecode":"050500"}]}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(AmapPOIService.AroundResponse.self, from: data)
        XCTAssertEqual(decoded.status, "1")
        XCTAssertEqual(decoded.infocode, "10000")
        XCTAssertEqual(decoded.pois?.count, 1)
        XCTAssertEqual(decoded.pois?.first?.name, "Café")
    }

    func testFlexibleDecoderAcceptsIntStatus() throws {
        // Some amap edge / proxy paths historically returned `status: 1` as
        // an int — the previous strict `String` decoder threw typeMismatch
        // and the EnrichmentAgent silently fell back to Overpass.
        let json = #"{"status":1,"info":"OK","infocode":10000,"pois":[]}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(AmapPOIService.AroundResponse.self, from: data)
        XCTAssertEqual(decoded.status, "1")
        XCTAssertEqual(decoded.infocode, "10000")
        XCTAssertEqual(decoded.pois?.count ?? 0, 0)
    }

    func testInfocodeHintCoversWellKnownErrors() {
        XCTAssertTrue(AmapPOIService.infocodeHint("10001").contains("INVALID_KEY"))
        XCTAssertTrue(AmapPOIService.infocodeHint("10009").contains("数字签名"))
        XCTAssertTrue(AmapPOIService.infocodeHint("10044").contains("USER_DAY_QUERY_OVER_LIMIT"))
        XCTAssertTrue(AmapPOIService.infocodeHint(nil).contains("unknown"))
        XCTAssertTrue(AmapPOIService.infocodeHint("99999").contains("unmapped"))
    }

    func testParseLocationRejectsOutOfRangeAndNaN() {
        // Defends against poisoned cache from a malformed amap response.
        XCTAssertNil(AmapPOIService.parseLocation("nan,nan"))
        XCTAssertNil(AmapPOIService.parseLocation("999,999"))   // out of range
        XCTAssertNil(AmapPOIService.parseLocation("0,0"))       // null island
        XCTAssertNil(AmapPOIService.parseLocation("114.0"))     // single value
        XCTAssertNil(AmapPOIService.parseLocation(""))
        XCTAssertNotNil(AmapPOIService.parseLocation("114.0579,22.5431"))
    }
}

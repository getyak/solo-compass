import XCTest
import CoreLocation
@testable import SoloCompass

/// Verifies the WGS84 ↔ GCJ-02 boundary conversion that isolates Amap's
/// "Mars coordinate" data from the app's WGS84 world (see `CoordinateConverter`
/// and ADR-amap-china-poi). Three properties matter:
///   1. The China gate fires for mainland points and not for Taiwan / HK /
///      Macau / overseas (those publish in WGS84 and must be left untouched).
///   2. The round trip WGS84 → GCJ-02 → WGS84 recovers the original to well
///      under a metre, so a converted Amap pin lands on the right street.
///   3. Outside the mainland the transform is the identity, so overseas
///      explore (Overpass) is bit-for-bit unaffected.
final class CoordinateConverterTests: XCTestCase {

    // Shenzhen Futian CBD — squarely inside the mainland.
    private let shenzhen = CLLocationCoordinate2D(latitude: 22.5431, longitude: 114.0579)
    // Beijing Tiananmen — canonical GCJ-02 test point.
    private let beijing = CLLocationCoordinate2D(latitude: 39.9087, longitude: 116.3975)
    // Chiang Mai old city — overseas.
    private let chiangMai = CLLocationCoordinate2D(latitude: 18.7877, longitude: 98.9938)
    // San Francisco — overseas (and negative longitude).
    private let sanFrancisco = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    // Taipei — inside the lat/lon box but carved out as WGS84 territory.
    private let taipei = CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)
    // Hong Kong Central — carved out (publishes WGS84).
    private let hongKong = CLLocationCoordinate2D(latitude: 22.2810, longitude: 114.1580)
    // Zhuhai Xiangzhou — mainland city core on the west bank of the Pearl River,
    // north of Macau. A too-wide HK+Macau box used to swallow it onto Overpass.
    private let zhuhai = CLLocationCoordinate2D(latitude: 22.2710, longitude: 113.5760)
    // Macau peninsula — SAR, publishes WGS84, must route overseas.
    private let macau = CLLocationCoordinate2D(latitude: 22.1987, longitude: 113.5439)
    // Hong Kong northern New Territories (Sheung Shui / Tai Po) — HK territory in
    // WGS84 that a 22.42°N upper bound used to misclassify as mainland.
    private let sheungShui = CLLocationCoordinate2D(latitude: 22.5010, longitude: 114.1280)
    private let taiPo = CLLocationCoordinate2D(latitude: 22.4501, longitude: 114.1640)

    // MARK: - China gate

    func testMainlandPointsAreInsideChina() {
        XCTAssertTrue(CoordinateConverter.isInsideChinaMainland(shenzhen))
        XCTAssertTrue(CoordinateConverter.isInsideChinaMainland(beijing))
    }

    func testOverseasPointsAreOutsideChina() {
        XCTAssertFalse(CoordinateConverter.isInsideChinaMainland(chiangMai))
        XCTAssertFalse(CoordinateConverter.isInsideChinaMainland(sanFrancisco))
    }

    func testTaiwanAndHongKongAreExcluded() {
        // Both sit inside the coarse lat/lon box but must route to the overseas
        // (WGS84 / Overpass) branch, so the gate must return false.
        XCTAssertFalse(CoordinateConverter.isInsideChinaMainland(taipei))
        XCTAssertFalse(CoordinateConverter.isInsideChinaMainland(hongKong))
    }

    func testZhuhaiIsMainland() {
        // Zhuhai is a real mainland city; it must route to Amap, not Overpass.
        // The narrowed Macau carve-out must NOT swallow it.
        XCTAssertTrue(CoordinateConverter.isInsideChinaMainland(zhuhai))
    }

    func testMacauIsExcluded() {
        // Macau SAR publishes WGS84 — must route overseas.
        XCTAssertFalse(CoordinateConverter.isInsideChinaMainland(macau))
    }

    func testHongKongNorthernNewTerritoriesAreExcluded() {
        // Northern NT (Sheung Shui, Tai Po) is HK territory in WGS84. The old
        // 22.42°N upper bound misclassified these as mainland and wrongly applied
        // the GCJ-02 offset to their WGS84 coordinates.
        XCTAssertFalse(CoordinateConverter.isInsideChinaMainland(sheungShui))
        XCTAssertFalse(CoordinateConverter.isInsideChinaMainland(taiPo))
    }

    func testShenzhenCBDStaysMainlandDespiteHKBoundary() {
        // The HK carve-out upper bound (~22.515°N) must keep Shenzhen's CBD
        // (22.5431°N) on the mainland Amap branch — the whole point of the
        // feature. Regression guard against over-extending the HK box north.
        XCTAssertTrue(CoordinateConverter.isInsideChinaMainland(shenzhen))
    }

    // MARK: - Round trip accuracy

    func testRoundTripIsSubMetreShenzhen() {
        assertRoundTripUnderOneMetre(shenzhen)
    }

    func testRoundTripIsSubMetreBeijing() {
        assertRoundTripUnderOneMetre(beijing)
    }

    /// WGS84 → GCJ-02 → WGS84 must return to the origin within 1 m.
    private func assertRoundTripUnderOneMetre(
        _ origin: CLLocationCoordinate2D,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let gcj = CoordinateConverter.wgs84ToGcj02(origin)
        let back = CoordinateConverter.gcj02ToWgs84(gcj)
        let originLoc = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let backLoc = CLLocation(latitude: back.latitude, longitude: back.longitude)
        let error = originLoc.distance(from: backLoc)
        XCTAssertLessThan(error, 1.0, "round-trip error \(error) m exceeds 1 m", file: file, line: line)
    }

    // MARK: - Offset is real and bounded inside China

    func testMainlandOffsetIsBetween50And700Metres() {
        // The GCJ-02 obfuscation shifts mainland points by hundreds of metres;
        // a near-zero shift would mean the transform silently no-op'd.
        let gcj = CoordinateConverter.wgs84ToGcj02(shenzhen)
        let origin = CLLocation(latitude: shenzhen.latitude, longitude: shenzhen.longitude)
        let shifted = CLLocation(latitude: gcj.latitude, longitude: gcj.longitude)
        let shift = origin.distance(from: shifted)
        XCTAssertGreaterThan(shift, 50.0, "expected a real Mars offset, got \(shift) m")
        XCTAssertLessThan(shift, 700.0, "offset \(shift) m is implausibly large")
    }

    // MARK: - Identity outside China

    func testOverseasConversionIsIdentity() {
        // Overseas the forward transform must leave the coordinate unchanged,
        // so the overseas explore path is unaffected by this code.
        let gcj = CoordinateConverter.wgs84ToGcj02(chiangMai)
        XCTAssertEqual(gcj.latitude, chiangMai.latitude, accuracy: 1e-12)
        XCTAssertEqual(gcj.longitude, chiangMai.longitude, accuracy: 1e-12)

        let back = CoordinateConverter.gcj02ToWgs84(sanFrancisco)
        XCTAssertEqual(back.latitude, sanFrancisco.latitude, accuracy: 1e-12)
        XCTAssertEqual(back.longitude, sanFrancisco.longitude, accuracy: 1e-12)
    }
}

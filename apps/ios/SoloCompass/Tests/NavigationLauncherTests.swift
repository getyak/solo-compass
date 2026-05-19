import XCTest
import CoreLocation
@testable import SoloCompass

@MainActor
final class NavigationLauncherTests: XCTestCase {

    // Asakusa Senso-ji, Tokyo — chosen as a representative WGS-84 coordinate.
    private let coordinate = CLLocationCoordinate2D(latitude: 35.7148, longitude: 139.7967)

    // MARK: - url(for:coordinate:name:)

    func test_url_appleMaps_returnsNil() {
        // Apple Maps is dispatched through MKMapItem.openInMaps, not a URL scheme.
        XCTAssertNil(NavigationLauncher.url(for: .appleMaps, coordinate: coordinate, name: "Senso-ji"))
    }

    func test_url_googleMaps_buildsExpectedDeepLink() {
        let url = NavigationLauncher.url(for: .googleMaps, coordinate: coordinate, name: "Senso-ji")
        XCTAssertNotNil(url)
        let s = url!.absoluteString
        XCTAssertTrue(s.hasPrefix("comgooglemaps://"), "got: \(s)")
        XCTAssertTrue(s.contains("daddr=35.7148,139.7967"), "missing daddr; got: \(s)")
        XCTAssertTrue(s.contains("q=Senso-ji"), "missing q; got: \(s)")
        XCTAssertTrue(s.contains("directionsmode=walking"), "missing walking mode; got: \(s)")
    }

    func test_url_amap_buildsExpectedDeepLinkWithDevZero() {
        let url = NavigationLauncher.url(for: .amap, coordinate: coordinate, name: "Senso-ji")
        XCTAssertNotNil(url)
        let s = url!.absoluteString
        XCTAssertTrue(s.hasPrefix("iosamap://path"), "got: \(s)")
        XCTAssertTrue(s.contains("dlat=35.7148"), "missing dlat; got: \(s)")
        XCTAssertTrue(s.contains("dlon=139.7967"), "missing dlon; got: \(s)")
        // dev=0 is critical: declares WGS-84 input so Amap converts to GCJ-02 internally.
        XCTAssertTrue(s.contains("dev=0"), "missing dev=0; got: \(s)")
        XCTAssertTrue(s.contains("t=2"), "missing walking mode t=2; got: \(s)")
    }

    func test_url_percentEncodesNonAsciiName() {
        let url = NavigationLauncher.url(for: .googleMaps, coordinate: coordinate, name: "浅草寺")
        XCTAssertNotNil(url)
        let s = url!.absoluteString
        XCTAssertFalse(s.contains("浅草寺"), "name should be percent-encoded; got: \(s)")
        XCTAssertTrue(s.contains("q=%E6%B5%85%E8%8D%89%E5%AF%BA"), "missing percent-encoded name; got: \(s)")
    }

    func test_url_nilName_producesEmptyQuery() {
        let url = NavigationLauncher.url(for: .googleMaps, coordinate: coordinate, name: nil)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("q=&"), "nil name should yield empty q=; got: \(url!.absoluteString)")
    }

    // MARK: - availableApps(canOpen:)

    func test_availableApps_alwaysIncludesAppleMaps_evenWhenNothingInstalled() {
        let apps = NavigationLauncher.availableApps { _ in false }
        XCTAssertEqual(apps, [.appleMaps])
    }

    func test_availableApps_includesGoogleWhenInstalled() {
        let apps = NavigationLauncher.availableApps { url in
            url.scheme == "comgooglemaps"
        }
        XCTAssertEqual(apps, [.appleMaps, .googleMaps])
    }

    func test_availableApps_includesAmapWhenInstalled() {
        let apps = NavigationLauncher.availableApps { url in
            url.scheme == "iosamap"
        }
        XCTAssertEqual(apps, [.appleMaps, .amap])
    }

    func test_availableApps_allInstalled_returnsCanonicalOrder() {
        let apps = NavigationLauncher.availableApps { _ in true }
        XCTAssertEqual(apps, [.appleMaps, .googleMaps, .amap])
    }
}

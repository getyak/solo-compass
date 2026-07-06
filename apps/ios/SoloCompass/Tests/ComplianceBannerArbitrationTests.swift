import XCTest
@testable import SoloCompass

/// City OS v2 §4.3: the top-banner arbitration ladder is offline > POI loading >
/// compliance. `CompassMapContentView.showsComplianceBanner` is the pure rung
/// for the compliance banner; every combination is pinned here so a future edit
/// to the banner block can't silently let it stack with the offline / loading
/// pills or show outside Live mode.
final class ComplianceBannerArbitrationTests: XCTestCase {

    private func shows(
        offline: Bool = false,
        fetching: Bool = false,
        cityOSEnabled: Bool = true,
        critical: Bool = true,
        dismissed: Bool = false,
        isLive: Bool = true
    ) -> Bool {
        CompassMapContentView.showsComplianceBanner(
            offline: offline,
            fetching: fetching,
            cityOSEnabled: cityOSEnabled,
            critical: critical,
            dismissed: dismissed,
            isLive: isLive
        )
    }

    func testShowsWhenCriticalLiveAndUndismissed() {
        XCTAssertTrue(shows())
    }

    func testOfflineWinsOverCompliance() {
        XCTAssertFalse(shows(offline: true))
    }

    func testLoadingWinsOverCompliance() {
        XCTAssertFalse(shows(fetching: true))
    }

    func testHiddenWhenFlagOff() {
        XCTAssertFalse(shows(cityOSEnabled: false))
    }

    func testHiddenWhenNotCritical() {
        XCTAssertFalse(shows(critical: false))
    }

    func testHiddenWhenDismissed() {
        XCTAssertFalse(shows(dismissed: true))
    }

    func testHiddenOutsideLiveMode() {
        XCTAssertFalse(shows(isLive: false))
    }
}

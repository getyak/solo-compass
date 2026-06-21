import XCTest
@testable import SoloCompass

/// `MapViewModel.classifyFailure` chooses the banner copy on an Explore
/// failure (offline vs slow service vs daily-quota hit vs generic 5xx). The
/// classifier is pure — it reads a single global `NetworkMonitor.shared` plus
/// the thrown error — so it's an ideal unit-test target. These tests pin
/// every branch so a future tweak (adding a URLError case, rebucketing
/// `.dnsLookupFailed`, …) doesn't silently flip the "you're offline" vs
/// "their server's slow" copy the user actually sees.
///
/// NetworkMonitor coupling: we reset `isConnected = true` in setUp/tearDown
/// via the `#if DEBUG` testing setter so a prior test's flip doesn't leak.
@MainActor
final class MapViewModelClassifyFailureTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        NetworkMonitor.shared._setConnectedForTesting(true)
    }

    override func tearDown() async throws {
        NetworkMonitor.shared._setConnectedForTesting(true)
        try await super.tearDown()
    }

    // MARK: - Offline branch (NetworkMonitor wins regardless of error)

    func testOfflineWinsRegardlessOfThrownError() {
        NetworkMonitor.shared._setConnectedForTesting(false)
        // Even a 500-style URLError must classify as .offline when the radio
        // is down — there's no point telling the user "service slow" if their
        // device has no path to the internet at all.
        let serverFlavoured = URLError(.badServerResponse)
        XCTAssertEqual(
            MapViewModel.classifyFailure(serverFlavoured),
            .offline
        )
    }

    func testOfflineWinsForGenericError() {
        NetworkMonitor.shared._setConnectedForTesting(false)
        struct Boom: Error {}
        XCTAssertEqual(MapViewModel.classifyFailure(Boom()), .offline)
    }

    // MARK: - URLError → apiTimeout bucket

    func testTimedOutMapsToApiTimeout() {
        XCTAssertEqual(
            MapViewModel.classifyFailure(URLError(.timedOut)),
            .apiTimeout
        )
    }

    func testCannotConnectToHostMapsToApiTimeout() {
        XCTAssertEqual(
            MapViewModel.classifyFailure(URLError(.cannotConnectToHost)),
            .apiTimeout
        )
    }

    func testCannotFindHostMapsToApiTimeout() {
        XCTAssertEqual(
            MapViewModel.classifyFailure(URLError(.cannotFindHost)),
            .apiTimeout
        )
    }

    func testNetworkConnectionLostMapsToApiTimeout() {
        XCTAssertEqual(
            MapViewModel.classifyFailure(URLError(.networkConnectionLost)),
            .apiTimeout
        )
    }

    func testDNSLookupFailedMapsToApiTimeout() {
        XCTAssertEqual(
            MapViewModel.classifyFailure(URLError(.dnsLookupFailed)),
            .apiTimeout
        )
    }

    // MARK: - URLError → offline bucket (no-radio family even when the
    // global NetworkMonitor is somehow stale during a fast transition)

    func testNotConnectedToInternetURLErrorMapsToOffline() {
        XCTAssertEqual(
            MapViewModel.classifyFailure(URLError(.notConnectedToInternet)),
            .offline,
            "URLError.notConnectedToInternet must classify as offline even " +
            "when the global NetworkMonitor hasn't caught up yet"
        )
    }

    func testDataNotAllowedURLErrorMapsToOffline() {
        XCTAssertEqual(
            MapViewModel.classifyFailure(URLError(.dataNotAllowed)),
            .offline
        )
    }

    // MARK: - URLError default → apiServerError

    func testBadServerResponseFallsThroughToApiServerError() {
        XCTAssertEqual(
            MapViewModel.classifyFailure(URLError(.badServerResponse)),
            .apiServerError
        )
    }

    func testUnsupportedURLFallsThroughToApiServerError() {
        XCTAssertEqual(
            MapViewModel.classifyFailure(URLError(.unsupportedURL)),
            .apiServerError
        )
    }

    // MARK: - Non-URLError defaults to apiServerError

    func testGenericErrorFallsBackToApiServerError() {
        struct Boom: Error {}
        XCTAssertEqual(
            MapViewModel.classifyFailure(Boom()),
            .apiServerError
        )
    }

    func testNSErrorFallsBackToApiServerError() {
        let nsErr = NSError(domain: "com.solocompass.test", code: -42)
        XCTAssertEqual(
            MapViewModel.classifyFailure(nsErr),
            .apiServerError
        )
    }
}

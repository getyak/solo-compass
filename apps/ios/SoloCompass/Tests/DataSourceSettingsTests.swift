import XCTest
@testable import SoloCompass

/// Covers the developer data-source configuration store: policy persistence,
/// fetch-limit defaults + clamping, and the policy → provider allow-flags that
/// `EnrichmentAgent.basePOIs` routes on.
final class DataSourceSettingsTests: XCTestCase {

    private let policyKey = "ds.policy"
    private let limitKey = "ds.poiFetchLimit"

    override func setUp() {
        super.setUp()
        // Start each test from a clean slate so defaults are exercised.
        UserDefaults.standard.removeObject(forKey: policyKey)
        UserDefaults.standard.removeObject(forKey: limitKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: policyKey)
        UserDefaults.standard.removeObject(forKey: limitKey)
        super.tearDown()
    }

    // MARK: - Policy

    func testPolicyDefaultsToBoth() {
        XCTAssertEqual(DataSourceSettings.policy, .both)
    }

    func testPolicyPersistsRoundTrip() {
        DataSourceSettings.policy = .amapOnly
        XCTAssertEqual(DataSourceSettings.policy, .amapOnly)
        DataSourceSettings.policy = .openMapOnly
        XCTAssertEqual(DataSourceSettings.policy, .openMapOnly)
    }

    func testUnknownStoredPolicyFallsBackToBoth() {
        UserDefaults.standard.set("garbage", forKey: policyKey)
        XCTAssertEqual(DataSourceSettings.policy, .both)
    }

    // MARK: - Allow-flags

    func testAllowFlagsPerPolicy() {
        XCTAssertTrue(DataSourcePolicy.both.allowsAmap)
        XCTAssertTrue(DataSourcePolicy.both.allowsOpenMap)

        XCTAssertTrue(DataSourcePolicy.amapOnly.allowsAmap)
        XCTAssertFalse(DataSourcePolicy.amapOnly.allowsOpenMap)

        XCTAssertFalse(DataSourcePolicy.openMapOnly.allowsAmap)
        XCTAssertTrue(DataSourcePolicy.openMapOnly.allowsOpenMap)
    }

    // MARK: - Fetch limit

    func testFetchLimitDefault() {
        XCTAssertEqual(DataSourceSettings.poiFetchLimit, DataSourceSettings.defaultPOIFetchLimit)
    }

    func testFetchLimitPersistsWithinRange() {
        DataSourceSettings.poiFetchLimit = 45
        XCTAssertEqual(DataSourceSettings.poiFetchLimit, 45)
    }

    func testFetchLimitClampsAboveMax() {
        DataSourceSettings.poiFetchLimit = 10_000
        XCTAssertEqual(DataSourceSettings.poiFetchLimit, DataSourceSettings.poiFetchLimitRange.upperBound)
    }

    func testFetchLimitClampsBelowMin() {
        DataSourceSettings.poiFetchLimit = 1
        XCTAssertEqual(DataSourceSettings.poiFetchLimit, DataSourceSettings.poiFetchLimitRange.lowerBound)
    }

    // MARK: - Reset

    func testResetRestoresDefaults() {
        DataSourceSettings.policy = .amapOnly
        DataSourceSettings.poiFetchLimit = 100
        DataSourceSettings.reset()
        XCTAssertEqual(DataSourceSettings.policy, .both)
        XCTAssertEqual(DataSourceSettings.poiFetchLimit, DataSourceSettings.defaultPOIFetchLimit)
    }
}

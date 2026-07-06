import XCTest
@testable import SoloCompass

/// City OS v2 §4.1: per-city mode state machine + once-only kit bookkeeping,
/// persisted through the `UserPreferences` blob.
@MainActor
final class CityOSStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "CityOSStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore() -> (CityOSStore, UserPreferences) {
        let prefs = UserPreferences(defaults: defaults)
        return (CityOSStore(preferences: prefs), prefs)
    }

    func testDefaultModeIsLive() {
        let (store, _) = makeStore()
        XCTAssertEqual(store.mode(for: "VTE"), .live)
        XCTAssertEqual(store.mode(for: nil), .live)
        XCTAssertEqual(store.mode(for: ""), .live)
    }

    func testSetModePersistsAcrossStoreReload() {
        let (store, _) = makeStore()
        store.setMode(.plan, for: "cmi")
        // A fresh store over a fresh prefs instance reads the same defaults.
        let (reloaded, _) = makeStore()
        XCTAssertEqual(reloaded.mode(for: "cmi"), .plan)
    }

    func testCityKeyIsCaseInsensitive() {
        let (store, _) = makeStore()
        store.setMode(.recall, for: "VTE")
        XCTAssertEqual(store.mode(for: "vte"), .recall, "iOS 大写城市码与 DB 小写约定必须互通")
        XCTAssertEqual(CityOSStore.normalizedCityKey(" VTE "), "vte")
    }

    func testCorruptModeRawFallsBackToLive() {
        let (store, prefs) = makeStore()
        prefs.cityModesRaw = ["vte": "teleport"] // unknown raw value
        XCTAssertEqual(store.mode(for: "vte"), .live)
    }

    func testKitSeenIsOnceOnlyPerCity() {
        let (store, _) = makeStore()
        XCTAssertFalse(store.hasSeenKit("VTE"))
        store.markKitSeen("VTE")
        XCTAssertTrue(store.hasSeenKit("vte"))
        XCTAssertFalse(store.hasSeenKit("cmi"), "别的城市不受影响")
    }
}

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

    // MARK: - City OS v3 · pre-trip checklist (Plan mode)

    func testKitTodoToggleRoundTripsAndPersists() {
        let (store, _) = makeStore()
        XCTAssertFalse(store.isKitTodoDone(.net, cityCode: "CMI"))
        store.toggleKitTodo(.net, cityCode: "CMI")
        XCTAssertTrue(store.isKitTodoDone(.net, cityCode: "cmi"), "城市码大小写互通")
        // Persists across a fresh store over the same defaults.
        let (reloaded, _) = makeStore()
        XCTAssertTrue(reloaded.isKitTodoDone(.net, cityCode: "cmi"))
        // Toggle back off.
        reloaded.toggleKitTodo(.net, cityCode: "cmi")
        XCTAssertFalse(reloaded.isKitTodoDone(.net, cityCode: "cmi"))
    }

    func testKitTodoDoneCountOnlyCountsKindsInKit() {
        let (store, _) = makeStore()
        store.toggleKitTodo(.net, cityCode: "cmi")
        store.toggleKitTodo(.visa, cityCode: "cmi")
        // Kit without the visa row: the stale visa tick must not inflate progress.
        let kit = [makeKitItem(kind: .net), makeKitItem(kind: .money)]
        XCTAssertEqual(store.kitTodoDoneCount(cityCode: "cmi", kit: kit), 1)
    }

    func testKitTodosAreScopedPerCity() {
        let (store, _) = makeStore()
        store.toggleKitTodo(.money, cityCode: "cmi")
        XCTAssertFalse(store.isKitTodoDone(.money, cityCode: "vte"), "别的城市不受影响")
    }

    // MARK: - City OS v3 · Recall 印证

    func testMarkVerifiedIsIdempotentAndPersists() {
        let (store, prefs) = makeStore()
        XCTAssertFalse(store.isVerified("x10kup"))
        store.markVerified("x10kup")
        store.markVerified("x10kup")
        XCTAssertTrue(store.isVerified("x10kup"))
        XCTAssertEqual(prefs.verifiedExperiences.count, 1)
        let (reloaded, _) = makeStore()
        XCTAssertTrue(reloaded.isVerified("x10kup"))
    }

    // MARK: - City OS v3 · lifecycle stage

    func testStageInference() {
        XCTAssertEqual(CityStage.inferred(mode: .live, daysStayed: 1), .land)
        XCTAssertEqual(CityStage.inferred(mode: .live, daysStayed: 2), .settle)
        XCTAssertEqual(CityStage.inferred(mode: .live, daysStayed: 3), .settle)
        XCTAssertEqual(CityStage.inferred(mode: .live, daysStayed: 4), .live)
        XCTAssertEqual(CityStage.inferred(mode: .live, daysStayed: nil), .live,
                       "没有入境日的 Live 城市停在稳态,不装知道")
        XCTAssertEqual(CityStage.inferred(mode: .live, daysStayed: 0), .live,
                       "入境日在未来 → daysStayed 0 → 稳态")
        XCTAssertEqual(CityStage.inferred(mode: .recall, daysStayed: 10), .leave)
        XCTAssertNil(CityStage.inferred(mode: .plan, daysStayed: nil),
                     "Plan 的停留还没开始,没有阶段")
    }

    func testStoreStageFollowsCityMode() {
        let (store, _) = makeStore()
        store.setMode(.recall, for: "lpq")
        XCTAssertEqual(store.stage(for: "lpq", daysStayed: nil), .leave)
        store.setMode(.plan, for: "cmi")
        XCTAssertNil(store.stage(for: "cmi", daysStayed: nil))
        XCTAssertEqual(store.stage(for: "vte", daysStayed: 1), .land)
    }

    // MARK: - inferMode (P1: automatic Live/Plan/Recall)

    func testInferModeLeaveStageWinsRecall() {
        let (store, _) = makeStore()
        // A finished stay reads as Recall regardless of the GPS signal.
        XCTAssertEqual(
            store.inferMode(for: "cmi", isUserInCity: true, stage: .leave),
            .recall,
            "已离城 (.leave) 无论 GPS 是否在城内都应回顾"
        )
        XCTAssertEqual(
            store.inferMode(for: "cmi", isUserInCity: false, stage: .leave),
            .recall
        )
    }

    func testInferModeInCityIsLive() {
        let (store, _) = makeStore()
        // A GPS fix inside the city, stay not ended → Live.
        XCTAssertEqual(
            store.inferMode(for: "vte", isUserInCity: true, stage: .live),
            .live
        )
        XCTAssertEqual(
            store.inferMode(for: "vte", isUserInCity: true, stage: nil),
            .live,
            "在城内且未离城 → 生活"
        )
    }

    func testInferModeFarAwayIsPlan() {
        let (store, _) = makeStore()
        // A far-away city (no nearby fix), stay not ended → Plan.
        XCTAssertEqual(
            store.inferMode(for: "lpq", isUserInCity: false, stage: nil),
            .plan
        )
        XCTAssertEqual(
            store.inferMode(for: "lpq", isUserInCity: false, stage: .live),
            .plan,
            "选了远城、GPS 不在城内 → 计划"
        )
    }

    // MARK: - Helpers

    private func makeKitItem(kind: CityKitItem.Kind) -> CityKitItem {
        CityKitItem(cityCode: "cmi", kind: kind, name: kind.rawValue, main: "main")
    }
}

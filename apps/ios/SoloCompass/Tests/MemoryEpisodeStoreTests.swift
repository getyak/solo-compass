import XCTest
@testable import SoloCompass

/// ③ Memory三层 slice A: retrieval quality unit tests.
///
/// The point of this suite: prove that the BM25-lite scorer surfaces the
/// obviously-relevant episode and ranks noise below the signal, in both
/// English and CJK. Slice B will swap the storage for SwiftData without
/// changing the interface — these tests come along unchanged.
@MainActor
final class MemoryEpisodeStoreTests: XCTestCase {

    private func fixedDate(_ offsetDays: Int = 0) -> Date {
        let base = Date(timeIntervalSince1970: 1_767_225_600)
        return base.addingTimeInterval(TimeInterval(offsetDays * 86_400))
    }

    private func seedStore() -> MemoryEpisodeStore {
        let store = MemoryEpisodeStore()
        store.insert(.init(
            occurredAt: fixedDate(-30),
            cityCode: "cmi",
            title: "Sunlit corner cafe in Chiang Mai",
            body: "Found a quiet coffee spot near Wat Phra Singh — great for solo work in the morning.",
            tags: ["coffee", "quiet", "morning"]
        ))
        store.insert(.init(
            occurredAt: fixedDate(-20),
            cityCode: "cmi",
            title: "Night market ramble",
            body: "Weekend walking street was loud but the mango sticky rice stall was worth it.",
            tags: ["food", "night", "market"]
        ))
        store.insert(.init(
            occurredAt: fixedDate(-15),
            cityCode: "szx",
            title: "岗厦北的星巴克",
            body: "在深圳福田区岗厦北地铁站附近的星巴克坐了一下午,写作效率不错。",
            tags: ["咖啡", "写作", "深圳"]
        ))
        store.insert(.init(
            occurredAt: fixedDate(-5),
            cityCode: "cmi",
            title: "Rainy day museum",
            body: "Chiang Mai City Arts and Cultural Centre was a great rainy-day pick.",
            tags: ["museum", "rainy"]
        ))
        return store
    }

    // MARK: - Tokenizer

    func testTokenizeSplitsASCIIByPunctuation() {
        XCTAssertEqual(
            MemoryEpisodeStore.tokenize("Hello, world! Let's-go."),
            ["hello", "world", "let", "s", "go"]
        )
    }

    func testTokenizeEmitsEachCJKCharacterSeparately() {
        XCTAssertEqual(MemoryEpisodeStore.tokenize("深圳咖啡"), ["深", "圳", "咖", "啡"])
    }

    func testTokenizeMixesCJKAndASCII() {
        XCTAssertEqual(
            MemoryEpisodeStore.tokenize("the 深圳 coffee spot"),
            ["the", "深", "圳", "coffee", "spot"]
        )
    }

    // MARK: - Retrieval

    func testCoffeeQuerySurfacesCoffeeEpisode() {
        let store = seedStore()
        let hits = store.search(query: "quiet coffee for solo work", limit: 3)
        XCTAssertFalse(hits.isEmpty, "must find at least one match")
        XCTAssertEqual(hits.first?.episode.title,
                       "Sunlit corner cafe in Chiang Mai",
                       "coffee query should rank the coffee episode first")
    }

    func testCityFilterHidesOtherCities() {
        let store = seedStore()
        let hits = store.search(query: "咖啡", cityCode: "cmi", limit: 5)
        XCTAssertFalse(hits.contains { $0.episode.cityCode == "szx" },
                       "cityCode filter must exclude other cities")
    }

    func testCJKQuerySurfacesCJKEpisode() {
        let store = seedStore()
        let hits = store.search(query: "深圳 咖啡 写作", limit: 3)
        XCTAssertEqual(hits.first?.episode.cityCode, "szx",
                       "CJK query should rank the SZX episode first")
        XCTAssertGreaterThan(hits.first?.score ?? 0, 0)
    }

    func testEmptyQueryReturnsNothing() {
        let store = seedStore()
        XCTAssertEqual(store.search(query: "").count, 0)
        XCTAssertEqual(store.search(query: "   ").count, 0)
    }

    func testGarbageQueryReturnsNothing() {
        let store = seedStore()
        XCTAssertEqual(store.search(query: "quantum flimflam").count, 0)
    }

    func testLimitIsRespected() {
        let store = seedStore()
        let hits = store.search(query: "coffee cafe", limit: 1)
        XCTAssertLessThanOrEqual(hits.count, 1)
    }

    // MARK: - Mutation

    func testRemoveAllClearsStore() {
        let store = seedStore()
        XCTAssertFalse(store.episodes.isEmpty)
        store.removeAll()
        XCTAssertTrue(store.episodes.isEmpty)
    }

    func testRemoveOlderThanCutoff() {
        let store = seedStore()
        store.removeOlder(than: fixedDate(-10))
        XCTAssertEqual(store.episodes.count, 1)
        XCTAssertEqual(store.episodes.first?.title, "Rainy day museum")
    }
}

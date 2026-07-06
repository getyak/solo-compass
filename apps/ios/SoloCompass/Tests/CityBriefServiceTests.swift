import XCTest
import SwiftData
@testable import SoloCompass

/// City OS v2: CityBriefService decode / cache / seed-fallback / expiry
/// behavior over an in-memory container (also proves `CityBriefCacheRecord`
/// is registered in the schema — same pattern as `V1_9SchemaRecordsTests`).
@MainActor
final class CityBriefServiceTests: XCTestCase {
    /// One `city_kits` row exactly as PostgREST returns it — snake_case keys
    /// and a fractional-seconds timestamptz, which `.iso8601` alone rejects.
    private let kitRowsJSON = Data("""
    [
      {
        "city_code": "vte",
        "section": "net",
        "name": "联网",
        "body": "Airalo 老挝 eSIM · 或 Unitel 门店",
        "lens_line": "机场到市区先用 eSIM，别机场柜台换卡",
        "health": "green",
        "last_verified_at": "2026-07-01T00:00:00.123456+00:00",
        "link_url": "https://www.airalo.com/laos-esim",
        "link_label": "Airalo",
        "action": { "type": "visa_reminder", "visa_days": 30, "tax_line_days": 183 }
      }
    ]
    """.utf8)

    private func eventsJSON(endsAt: String) -> Data {
        Data("""
        [
          {
            "id": "evt_vte_test_20260710",
            "city_code": "vte",
            "name": "测试市集",
            "category": "market",
            "when_label": "周五傍晚",
            "starts_at": "2026-07-10T10:00:00Z",
            "ends_at": "\(endsAt)",
            "solo_score": 8.5,
            "solo_note": "一个人逛正好",
            "health": "green",
            "seen_label": "人工策展",
            "lat": 17.9648,
            "lng": 102.6108,
            "limited_label": "本周五限时",
            "source_url": "https://www.tourismlaos.org/events"
          }
        ]
        """.utf8)
    }

    private func makeService(seed: Data? = nil) -> CityBriefService {
        CityBriefService(
            container: SoloCompassModelContainer.makeInMemory(),
            seedLoader: { _ in seed }
        )
    }

    // MARK: - Decoding

    func testDecodesServerRowShape() throws {
        let rows = try CityBriefService.decoder.decode([CityKitItem].self, from: kitRowsJSON)
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.kind, .net)
        XCTAssertEqual(row.main, "Airalo 老挝 eSIM · 或 Unitel 门店")
        XCTAssertEqual(row.lens, "机场到市区先用 eSIM，别机场柜台换卡")
        XCTAssertEqual(row.linkLabel, "Airalo")
        XCTAssertNotNil(row.lastVerifiedAt, "fractional-seconds timestamptz must decode")
        XCTAssertEqual(row.action?.visaDays, 30)
        XCTAssertEqual(row.id, "vte.net")
    }

    func testDecodesEventRowAndNoticeFlag() throws {
        let events = try CityBriefService.decoder.decode([CityEvent].self, from: eventsJSON(endsAt: "2026-07-10T14:00:00Z"))
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.soloScore, 8.5)
        XCTAssertFalse(event.isNotice)
        XCTAssertEqual(event.sourceURL?.host, "www.tourismlaos.org")
    }

    // MARK: - Cache path

    func testLoadPublishesFromFreshCacheWithoutSeed() async throws {
        let container = SoloCompassModelContainer.makeInMemory()
        let context = ModelContext(container)
        context.insert(CityBriefCacheRecord(
            cityCode: "vte",
            kitJSON: kitRowsJSON,
            eventsJSON: eventsJSON(endsAt: "2100-01-01T00:00:00Z"),
            fetchedAt: Date() // fresh — no refresh attempt
        ))
        try context.save()

        let service = CityBriefService(container: container, seedLoader: { _ in nil })
        await service.load(cityCode: "VTE") // uppercase in, lowercase storage
        XCTAssertEqual(service.loadedCityCode, "vte")
        XCTAssertEqual(service.kit.count, 1)
        XCTAssertEqual(service.events.count, 1)
    }

    func testActiveEventsFiltersExpired() async throws {
        let container = SoloCompassModelContainer.makeInMemory()
        let context = ModelContext(container)
        context.insert(CityBriefCacheRecord(
            cityCode: "vte",
            kitJSON: kitRowsJSON,
            eventsJSON: eventsJSON(endsAt: "2020-01-01T00:00:00Z"), // long past
            fetchedAt: Date()
        ))
        try context.save()

        let service = CityBriefService(container: container, seedLoader: { _ in nil })
        await service.load(cityCode: "vte")
        XCTAssertEqual(service.events.count, 1, "cache keeps the row")
        XCTAssertTrue(service.activeEvents().isEmpty, "expired events never render")
    }

    // MARK: - Seed fallback

    func testSeedFallbackWhenCacheAndNetworkEmpty() async {
        let seed = Data("""
        { "kit": \(String(data: kitRowsJSON, encoding: .utf8)!),
          "events": \(String(data: eventsJSON(endsAt: "2100-01-01T00:00:00Z"), encoding: .utf8)!) }
        """.utf8)
        let service = makeService(seed: seed)
        await service.load(cityCode: "vte")
        XCTAssertEqual(service.kit.count, 1, "bundled seed must fill the void")
        XCTAssertEqual(service.events.count, 1)
        XCTAssertTrue(service.hasKit(for: "VTE"))
    }

    func testBundledVteSeedResourceDecodes() throws {
        // The real bundled seed must stay decodable — this is the offline
        // first-run experience for 万象.
        let bundle = Bundle(for: type(of: self))
        let url = Bundle.main.url(forResource: "seed_city_brief_vte", withExtension: "json")
            ?? bundle.url(forResource: "seed_city_brief_vte", withExtension: "json")
        guard let url else {
            throw XCTSkip("seed_city_brief_vte.json not bundled into this test host")
        }
        let data = try Data(contentsOf: url)
        struct SeedShape: Decodable {
            let kit: [CityKitItem]
            let events: [CityEvent]
        }
        let seed = try CityBriefService.decoder.decode(SeedShape.self, from: data)
        XCTAssertEqual(seed.kit.count, 4, "kit is exactly the four sections")
        XCTAssertEqual(Set(seed.kit.map(\.kind)), Set(CityKitItem.Kind.allCases))
        XCTAssertGreaterThanOrEqual(seed.events.count, 3)
        XCTAssertTrue(seed.events.contains(where: \.isNotice), "seed carries one notice")
    }
}

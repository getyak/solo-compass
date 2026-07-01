import XCTest
@testable import SoloCompass

/// Tests for the P3.4 #340 print-partner surface. Covers the LuluMock
/// adapter's contract: pricing tiers, idempotency, and status progression.
/// The protocol + value types are also exercised implicitly — any drift
/// (e.g. renaming `orderId`) will break these tests, protecting future
/// concrete adapters from silent API breakage.
final class PrintFulfillmentClientTests: XCTestCase {

    // MARK: - Fixtures

    private func makeManifest(chapterCount: Int) -> BookManifest {
        let chapters = (1...max(chapterCount, 1)).map { week in
            BookChapter(
                weekOfYear: week,
                startDate: Date(timeIntervalSince1970: TimeInterval(week) * 604_800),
                visitCount: 3,
                experienceTitles: ["Cafe \(week)"]
            )
        }
        return BookManifest(
            year: 2026,
            approxPageCount: 2 + chapters.count * 2,
            chapters: chapters,
            coverCaption: "test cover",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)  // stable
        )
    }

    private func makeAddress(country: String = "US") -> PrintShippingAddress {
        PrintShippingAddress(
            fullName: "Solo Traveler",
            line1: "1 Test St",
            line2: nil,
            city: "Testville",
            region: "CA",
            postalCode: "94000",
            countryCode: country
        )
    }

    // MARK: - Pricing tiers

    func testEstimatePriceRejectsEmptyManifest() async {
        let client = LuluMockFulfillmentClient()
        let empty = BookManifest(
            year: 2026, approxPageCount: 2, chapters: [],
            coverCaption: "", createdAt: Date()
        )
        do {
            _ = try await client.estimatePrice(manifest: empty, shippingCountryCode: "US")
            XCTFail("estimatePrice must throw on empty manifest")
        } catch let PrintFulfillmentError.invalidManifest(reason) {
            XCTAssertEqual(reason, "no chapters")
        } catch {
            XCTFail("expected .invalidManifest, got \(error)")
        }
    }

    func testEstimatePricePicksTierByChapterCount() async throws {
        let client = LuluMockFulfillmentClient()

        let small = try await client.estimatePrice(
            manifest: makeManifest(chapterCount: 5), shippingCountryCode: "US")
        let mid = try await client.estimatePrice(
            manifest: makeManifest(chapterCount: 30), shippingCountryCode: "US")
        let large = try await client.estimatePrice(
            manifest: makeManifest(chapterCount: 60), shippingCountryCode: "US")

        XCTAssertEqual(small.unitPriceCents, 2999,  "5 chapters → base tier")
        XCTAssertEqual(mid.unitPriceCents,   3999,  "30 chapters → 25+ tier")
        XCTAssertEqual(large.unitPriceCents, 4499,  "60 chapters → 50+ tier")
    }

    func testShippingDiffersByCountryCode() async throws {
        let client = LuluMockFulfillmentClient()
        let usQuote = try await client.estimatePrice(
            manifest: makeManifest(chapterCount: 10), shippingCountryCode: "US")
        let cnQuote = try await client.estimatePrice(
            manifest: makeManifest(chapterCount: 10), shippingCountryCode: "CN")
        XCTAssertEqual(usQuote.shippingCents, 599)
        XCTAssertEqual(cnQuote.shippingCents, 1499)
        XCTAssertEqual(usQuote.etaBusinessDays, 7)
        XCTAssertEqual(cnQuote.etaBusinessDays, 14)
        XCTAssertEqual(usQuote.currencyCode, "USD")
    }

    // MARK: - Idempotent submitOrder

    func testSubmitOrderIsIdempotentPerKey() async throws {
        let client = LuluMockFulfillmentClient()
        let key = "test-idempotency-key-1"
        let req = PrintOrderRequest(
            manifest: makeManifest(chapterCount: 12),
            pdfURL: URL(string: "https://cdn.example.com/book.pdf")!,
            shippingAddress: makeAddress(),
            idempotencyKey: key
        )

        let first = try await client.submitOrder(req)
        let second = try await client.submitOrder(req)

        XCTAssertEqual(first.orderId, second.orderId,
                       "Retry with same idempotency key must return SAME order — else duplicate charge")
        XCTAssertEqual(first.paidCents, second.paidCents)
        XCTAssertEqual(first.orderId, "mock-\(key)")
    }

    func testSubmitOrderTotalsShippingIntoPaidCents() async throws {
        let client = LuluMockFulfillmentClient()
        let req = PrintOrderRequest(
            manifest: makeManifest(chapterCount: 30),  // → 3999 unit
            pdfURL: URL(string: "https://cdn.example.com/b.pdf")!,
            shippingAddress: makeAddress(country: "US"),   // → 599 shipping
            idempotencyKey: UUID().uuidString
        )
        let receipt = try await client.submitOrder(req)
        XCTAssertEqual(receipt.paidCents, 3999 + 599)
        XCTAssertEqual(receipt.currencyCode, "USD")
    }

    // MARK: - Status polling progression

    func testPollStatusAdvancesPerPollCount() async throws {
        let client = LuluMockFulfillmentClient()
        let req = PrintOrderRequest(
            manifest: makeManifest(chapterCount: 10),
            pdfURL: URL(string: "https://cdn.example.com/b.pdf")!,
            shippingAddress: makeAddress(),
            idempotencyKey: "progression-test"
        )
        let receipt = try await client.submitOrder(req)

        let s1 = try await client.pollStatus(orderId: receipt.orderId)
        let s2 = try await client.pollStatus(orderId: receipt.orderId)
        let s3 = try await client.pollStatus(orderId: receipt.orderId)
        let s4 = try await client.pollStatus(orderId: receipt.orderId)

        XCTAssertEqual(s1, .accepted)
        XCTAssertEqual(s2, .inProduction)
        XCTAssertEqual(s3, .shipped)
        XCTAssertEqual(s4, .delivered)
    }

    func testPollStatusOnUnknownOrderThrows() async {
        let client = LuluMockFulfillmentClient()
        do {
            _ = try await client.pollStatus(orderId: "does-not-exist")
            XCTFail("pollStatus must throw on unknown orderId")
        } catch let PrintFulfillmentError.orderNotFound(id) {
            XCTAssertEqual(id, "does-not-exist")
        } catch {
            XCTFail("expected .orderNotFound, got \(error)")
        }
    }

    /// The partner-neutral status enum is on the WIRE — every adapter must
    /// map its partner-internal states to these 6 rawValues. Renaming a
    /// case after ship would break stored orders' decode.
    func testStatusEnumRawValuesAreStable() {
        XCTAssertEqual(PrintOrderStatus.accepted.rawValue,     "accepted")
        XCTAssertEqual(PrintOrderStatus.inProduction.rawValue, "inProduction")
        XCTAssertEqual(PrintOrderStatus.shipped.rawValue,      "shipped")
        XCTAssertEqual(PrintOrderStatus.delivered.rawValue,    "delivered")
        XCTAssertEqual(PrintOrderStatus.cancelled.rawValue,    "cancelled")
        XCTAssertEqual(PrintOrderStatus.failed.rawValue,       "failed")
    }
}

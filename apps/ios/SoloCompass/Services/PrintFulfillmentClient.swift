import Foundation
import os

/// Print-fulfillment surface for the year-end Travel Book (Phase 3 P3.4 #340).
///
/// This is the code-side of the print-partner spike: a stable protocol plus
/// a Lulu-shaped mock adapter so the Archive banner CTA (#342) can wire
/// through to a *real* order-submission call site today, even before the
/// business signs a contract. When a partner is chosen the concrete adapter
/// (`LuluClient` / `ShutterflyClient` / `一印Client`) drops in behind the
/// same protocol — no ArchiveView / BookComposeService changes needed.
///
/// Contract shape mirrors what every print-on-demand REST API exposes:
///   1. `estimatePrice(manifest:shippingCountryCode:)` — pre-flight quote
///   2. `submitOrder(request:)` — actual PDF/manifest upload + order create
///   3. `pollStatus(orderId:)` — long-poll until printed/shipped/delivered
///
/// A conforming adapter never mutates client state — the return values are
/// the whole story. The caller stores order IDs / state in SwiftData
/// (`BookOrderRecord`, to land alongside a real partner) and drives the
/// UI off that store.
public protocol PrintFulfillmentClient: Sendable {

    /// Estimate the printed unit cost in USD cents (fixed-point avoids
    /// float rounding in receipts). Partners quote by page-count tiers +
    /// shipping region, so pass both.
    func estimatePrice(
        manifest: BookManifest,
        shippingCountryCode: String
    ) async throws -> PrintPriceEstimate

    /// Submit an order. The `request` carries manifest + destination + a
    /// pre-signed URL to the composed PDF. Returns a partner-owned order
    /// ID for polling.
    func submitOrder(_ request: PrintOrderRequest) async throws -> PrintOrderReceipt

    /// Poll for order state. Idempotent — safe to call at any cadence.
    /// Callers should back off (e.g. 30s → 5min → 1h) as state advances.
    func pollStatus(orderId: String) async throws -> PrintOrderStatus
}

// MARK: - Value types (partner-neutral)

public struct PrintPriceEstimate: Codable, Hashable, Sendable {
    public let unitPriceCents: Int
    public let shippingCents: Int
    public let currencyCode: String   // ISO 4217 — "USD", "CNY", etc.
    public let etaBusinessDays: Int

    public var totalCents: Int { unitPriceCents + shippingCents }

    public init(unitPriceCents: Int, shippingCents: Int,
                currencyCode: String, etaBusinessDays: Int) {
        self.unitPriceCents = unitPriceCents
        self.shippingCents = shippingCents
        self.currencyCode = currencyCode
        self.etaBusinessDays = etaBusinessDays
    }
}

public struct PrintOrderRequest: Codable, Hashable, Sendable {
    public let manifest: BookManifest
    public let pdfURL: URL
    public let shippingAddress: PrintShippingAddress
    public let quantity: Int
    public let idempotencyKey: String  // client-generated UUID for retry safety

    public init(manifest: BookManifest, pdfURL: URL,
                shippingAddress: PrintShippingAddress,
                quantity: Int = 1, idempotencyKey: String) {
        self.manifest = manifest
        self.pdfURL = pdfURL
        self.shippingAddress = shippingAddress
        self.quantity = quantity
        self.idempotencyKey = idempotencyKey
    }
}

public struct PrintShippingAddress: Codable, Hashable, Sendable {
    public let fullName: String
    public let line1: String
    public let line2: String?
    public let city: String
    public let region: String       // state / province
    public let postalCode: String
    public let countryCode: String  // ISO 3166 alpha-2

    public init(fullName: String, line1: String, line2: String? = nil,
                city: String, region: String, postalCode: String,
                countryCode: String) {
        self.fullName = fullName
        self.line1 = line1
        self.line2 = line2
        self.city = city
        self.region = region
        self.postalCode = postalCode
        self.countryCode = countryCode
    }
}

public struct PrintOrderReceipt: Codable, Hashable, Sendable {
    public let orderId: String        // partner-owned
    public let acceptedAt: Date
    public let estimatedShipDate: Date?
    public let paidCents: Int
    public let currencyCode: String

    public init(orderId: String, acceptedAt: Date,
                estimatedShipDate: Date?, paidCents: Int, currencyCode: String) {
        self.orderId = orderId
        self.acceptedAt = acceptedAt
        self.estimatedShipDate = estimatedShipDate
        self.paidCents = paidCents
        self.currencyCode = currencyCode
    }
}

/// Partner-neutral status timeline. Adapters MUST map their partner's
/// internal states into this closed set — never leak partner-specific
/// strings past the adapter boundary.
public enum PrintOrderStatus: String, Codable, Hashable, Sendable {
    case accepted        // received, not yet in print queue
    case inProduction    // physically being printed / bound
    case shipped         // handed to carrier
    case delivered       // confirmed at address
    case cancelled       // by user or partner (refunded)
    case failed          // permanent partner error (refunded)
}

// MARK: - Errors

public enum PrintFulfillmentError: Error, Equatable, Sendable {
    case invalidManifest(String)
    case partnerUnavailable
    case pdfNotReachable
    case duplicateIdempotencyKey
    case orderNotFound(String)
    case underlying(String)
}

// MARK: - Lulu-shaped mock adapter

/// In-memory adapter matching Lulu's API shape so we can wire the Archive
/// banner CTA + BookComposeService end-to-end without a live partner.
/// Deterministic outputs make this test-friendly: same input → same order ID.
///
/// **NOT for production.** Real Lulu integration replaces this with a
/// URLSession-backed adapter reading a bearer token from Keychain.
public actor LuluMockFulfillmentClient: PrintFulfillmentClient {

    private static let log = OSLog(subsystem: "com.solocompass.app",
                                   category: "PrintMock")

    /// Storage keyed by orderId. `polls` lets pollStatus() advance state
    /// deterministically across calls (accepted → inProduction → shipped).
    private var orders: [String: (receipt: PrintOrderReceipt, polls: Int)] = [:]

    /// Deterministic pricing table by chapter count. Lulu's real tiers are
    /// per-page; this collapses to per-chapter (2 pages/chapter) for v1.
    private let unitPriceTable: [(chapters: Int, cents: Int)] = [
        (0, 2999),
        (10, 3499),
        (25, 3999),
        (50, 4499),
        (100, 4999),
    ]

    public init() {}

    public func estimatePrice(
        manifest: BookManifest,
        shippingCountryCode: String
    ) async throws -> PrintPriceEstimate {
        guard !manifest.chapters.isEmpty else {
            throw PrintFulfillmentError.invalidManifest("no chapters")
        }
        let n = manifest.chapters.count
        let unit = unitPriceTable.last(where: { $0.chapters <= n })?.cents ?? 2999
        let shipping = shippingCountryCode == "US" ? 599 : 1499
        let eta = shippingCountryCode == "US" ? 7 : 14
        return PrintPriceEstimate(
            unitPriceCents: unit,
            shippingCents: shipping,
            currencyCode: "USD",
            etaBusinessDays: eta
        )
    }

    public func submitOrder(_ request: PrintOrderRequest) async throws -> PrintOrderReceipt {
        // Idempotency: a retry with the same key returns the SAME order.
        let orderId = "mock-\(request.idempotencyKey)"
        if let existing = orders[orderId] {
            return existing.receipt
        }
        let quote = try await estimatePrice(
            manifest: request.manifest,
            shippingCountryCode: request.shippingAddress.countryCode
        )
        let receipt = PrintOrderReceipt(
            orderId: orderId,
            acceptedAt: request.manifest.createdAt,   // stable, testable
            estimatedShipDate: nil,                   // no clock in tests
            paidCents: quote.totalCents,
            currencyCode: quote.currencyCode
        )
        orders[orderId] = (receipt, 0)
        os_log("LuluMock: submitted order %{public}@ paid=%d",
               log: Self.log, type: .info, orderId, receipt.paidCents)
        return receipt
    }

    public func pollStatus(orderId: String) async throws -> PrintOrderStatus {
        guard var entry = orders[orderId] else {
            throw PrintFulfillmentError.orderNotFound(orderId)
        }
        entry.polls += 1
        orders[orderId] = entry
        switch entry.polls {
        case 1: return .accepted
        case 2: return .inProduction
        case 3: return .shipped
        default: return .delivered
        }
    }
}

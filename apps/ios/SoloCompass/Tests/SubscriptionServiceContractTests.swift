import XCTest
@testable import SoloCompass

/// Contract tests for `SubscriptionService` (P3.0 #304 + P2.1 #214/#215
/// + P3.1 #313 + P3.2 #323 + P2.3 #234).
///
/// Full `StoreKit2` purchase round-trips need a live sandbox account we
/// can't authenticate against from a unit-test harness. So this suite
/// pins the surface that DOES matter in unit tests:
///   1. Product ID rawValues (on the wire to App Store Connect — renaming
///      after submitting SKUs orphans users' receipts).
///   2. The `allConsumableProductIDs` + `allCatalogProductIDs` composition
///      (the paywall + tool router look up product objects by these lists).
///   3. Admin allow-list normalization (whitespace + case tolerance).
///   4. Entitlement enum raw-value stability (persisted in Keychain).
@MainActor
final class SubscriptionServiceContractTests: XCTestCase {

    // MARK: - Product ID rawValues (contract with App Store Connect)

    func testAllProductIDsRawValuesArePinned() {
        XCTAssertEqual(SubscriptionService.monthlyProductID,
                       "com.solocompass.pro.monthly")
        XCTAssertEqual(SubscriptionService.yearlyProductID,
                       "com.solocompass.pro.yearly")
        XCTAssertEqual(SubscriptionService.blindboxSingleProductID,
                       "com.solocompass.consumable.blindbox.single")
        XCTAssertEqual(SubscriptionService.sosSingleProductID,
                       "com.solocompass.consumable.sos.single")
        XCTAssertEqual(SubscriptionService.unwalkedSingleProductID,
                       "com.solocompass.consumable.unwalked.single")
        XCTAssertEqual(SubscriptionService.omenRerollProductID,
                       "com.solocompass.consumable.omen.reroll")
        XCTAssertEqual(SubscriptionService.ostRerollProductID,
                       "com.solocompass.consumable.ost.reroll")
        XCTAssertEqual(SubscriptionService.bragVideoProductID,
                       "com.solocompass.consumable.brag.video")
    }

    func testAllConsumableProductIDsIsCompleteAndOrdered() {
        let expected: [String] = [
            SubscriptionService.blindboxSingleProductID,
            SubscriptionService.sosSingleProductID,
            SubscriptionService.unwalkedSingleProductID,
            SubscriptionService.omenRerollProductID,
            SubscriptionService.ostRerollProductID,
            SubscriptionService.bragVideoProductID,
        ]
        XCTAssertEqual(SubscriptionService.allConsumableProductIDs, expected)
    }

    func testAllCatalogProductIDsMergesSubscriptionsAndConsumables() {
        let catalog = SubscriptionService.allCatalogProductIDs
        XCTAssertEqual(catalog.count, 2 + 6)
        XCTAssertTrue(catalog.contains(SubscriptionService.monthlyProductID))
        XCTAssertTrue(catalog.contains(SubscriptionService.yearlyProductID))
        for consumable in SubscriptionService.allConsumableProductIDs {
            XCTAssertTrue(catalog.contains(consumable),
                          "\(consumable) missing from allCatalogProductIDs")
        }
    }

    func testCatalogHasNoDuplicateProductIDs() {
        let ids = SubscriptionService.allCatalogProductIDs
        XCTAssertEqual(Set(ids).count, ids.count,
                       "duplicate product ID in allCatalogProductIDs — check the merge")
    }

    // MARK: - Product ID naming convention

    func testProductIDsFollowNamingConvention() {
        for id in SubscriptionService.allProductIDs {
            XCTAssertTrue(id.hasPrefix("com.solocompass.pro."),
                          "\(id) must live in pro subscription namespace")
        }
        for id in SubscriptionService.allConsumableProductIDs {
            XCTAssertTrue(id.hasPrefix("com.solocompass.consumable."),
                          "\(id) must live in consumable namespace")
        }
    }

    // MARK: - Admin allow-list normalization

    func testIsAdminEmailIsCaseInsensitive() {
        XCTAssertTrue(SubscriptionService.isAdminEmail("XIONG3293172751@OUTLOOK.COM"))
        XCTAssertTrue(SubscriptionService.isAdminEmail("xiong3293172751@outlook.com"))
        XCTAssertTrue(SubscriptionService.isAdminEmail("Xiong3293172751@Outlook.com"))
    }

    func testIsAdminEmailTrimsWhitespace() {
        XCTAssertTrue(SubscriptionService.isAdminEmail("  xiong3293172751@outlook.com  "))
        XCTAssertTrue(SubscriptionService.isAdminEmail("\txiong3293172751@outlook.com\n"))
    }

    func testIsAdminEmailRejectsUnrelatedEmails() {
        XCTAssertFalse(SubscriptionService.isAdminEmail("someone.else@example.com"))
        XCTAssertFalse(SubscriptionService.isAdminEmail(""))
        XCTAssertFalse(SubscriptionService.isAdminEmail("   "))
    }

    // MARK: - Entitlement enum stability

    /// `Entitlement.rawValue` is persisted (Keychain fast-path cache) so a
    /// rename after ship would silently downgrade every returning Pro
    /// user to `.free` at cold-start.
    func testEntitlementRawValuesAreStable() {
        XCTAssertEqual(SubscriptionService.Entitlement.free.rawValue,       "free")
        XCTAssertEqual(SubscriptionService.Entitlement.proTrial.rawValue,   "proTrial")
        XCTAssertEqual(SubscriptionService.Entitlement.pro.rawValue,        "pro")
        XCTAssertEqual(SubscriptionService.Entitlement.proExpired.rawValue, "proExpired")
    }

    func testAllEntitlementCasesEnumerated() {
        XCTAssertEqual(SubscriptionService.Entitlement.allCases.count, 4)
    }
}

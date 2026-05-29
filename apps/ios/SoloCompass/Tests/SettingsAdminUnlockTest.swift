import XCTest
@testable import SoloCompass

// US-044: Regression coverage for SettingsView's "secret" admin / tester
// unlock flow. The Subscription section shows an "Unlock with tester email"
// button that opens an alert with a single TextField (`adminEmailInput`).
// Tapping "Unlock" runs `runAdminUnlock()`, which forwards the typed string
// to `SubscriptionService.unlockWithAdminEmail(_:)`. When the email is on the
// allow-list the entitlement flips to `.pro` (the "admin flag set"); otherwise
// nothing changes. These tests exercise that exact code path without altering
// behavior.
@MainActor
final class SettingsAdminUnlockTest: XCTestCase {

    /// Mirrors SettingsView.runAdminUnlock(): forward the alert's text field
    /// contents to unlockWithAdminEmail and surface a result toast.
    private func runAdminUnlock(
        on service: SubscriptionService,
        emailInput: String
    ) -> Bool {
        // Same call SettingsView makes; the bool drives which toast string
        // it shows (settings.adminUnlock.success / .failure).
        service.unlockWithAdminEmail(emailInput)
    }

    func testAllowListedEmailSetsAdminProEntitlement() {
        let service = SubscriptionService()
        // Seed a known non-Pro baseline so the assertion is meaningful even on
        // DEBUG builds that default to .pro via FF_DEBUG_FORCE_PRO.
        service._setEntitlementForTesting(.free)
        XCTAssertFalse(service.entitlement.isActive,
                       "Precondition: tester starts without Pro before the unlock")

        // The secret sequence: type an allow-listed email into the unlock
        // alert and tap Unlock.
        let adminEmail = SubscriptionService.adminEmails.first!
        let unlocked = runAdminUnlock(on: service, emailInput: adminEmail)

        XCTAssertTrue(unlocked, "An allow-listed email must report a successful unlock")
        XCTAssertEqual(service.entitlement, .pro,
                       "Admin unlock must flip the entitlement flag to .pro")
        XCTAssertTrue(service.entitlement.isActive,
                      "Unlocked tester must have an active (Pro) entitlement")
    }

    func testAdminUnlockIsCaseAndWhitespaceTolerant() {
        let service = SubscriptionService()
        service._setEntitlementForTesting(.free)

        // SettingsView's TextField uses .never autocapitalization, but users
        // still fat-finger casing and trailing spaces — the unlock normalizes.
        let messyInput = "  \(SubscriptionService.adminEmails.first!.uppercased())  "
        let unlocked = runAdminUnlock(on: service, emailInput: messyInput)

        XCTAssertTrue(unlocked, "Unlock must tolerate surrounding whitespace and casing")
        XCTAssertEqual(service.entitlement, .pro)
    }

    func testNonAllowListedEmailDoesNotUnlock() {
        let service = SubscriptionService()
        service._setEntitlementForTesting(.free)

        let unlocked = runAdminUnlock(on: service, emailInput: "stranger@example.com")

        XCTAssertFalse(unlocked, "A non-allow-listed email must not unlock Pro")
        XCTAssertEqual(service.entitlement, .free,
                       "A rejected unlock must leave the entitlement untouched")
        XCTAssertFalse(service.entitlement.isActive)
    }

    func testEmptyEmailDoesNotUnlock() {
        let service = SubscriptionService()
        service._setEntitlementForTesting(.free)

        // Default state of the alert's adminEmailInput before the user types.
        let unlocked = runAdminUnlock(on: service, emailInput: "")

        XCTAssertFalse(unlocked, "An empty email field must not unlock Pro")
        XCTAssertEqual(service.entitlement, .free)
    }
}

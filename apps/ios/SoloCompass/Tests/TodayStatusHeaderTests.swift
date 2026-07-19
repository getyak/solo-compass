import XCTest
import SwiftUI
@testable import SoloCompass

/// Nomad OS B1-b: `TodayStatusHeader` derives city / day / face / visa from
/// independent sources, not the map's `MapViewModel`. These pin the pure
/// derivations that the header shows — most importantly that the city name
/// resolves from the now-`static` `MapViewModel.cityNameMap` (the single source
/// of truth shared with the map pill), and that the visa ring's three-state
/// logic keys off compliance state existing.
@MainActor
final class TodayStatusHeaderTests: XCTestCase {

    /// The name map went `static` so Today and the map pill agree without a
    /// shared view model. Guard the codes Today will most often see.
    func testCityNameMapResolvesSharedNames() {
        XCTAssertEqual(MapViewModel.cityNameMap["SZX"], "Shenzhen")
        XCTAssertEqual(MapViewModel.cityNameMap["CNX"], "Chiang Mai")
        XCTAssertEqual(MapViewModel.cityNameMap["VTE"], "Vientiane")
        XCTAssertEqual(MapViewModel.cityNameMap["lisbon"], "Lisbon")
    }

    /// Face derivation is pure `BaseFace.derive(mode:stage:)`; a Live city with
    /// no stage rests at `.live`, land/settle read as arriving.
    func testFaceDerivationMatchesLifecycle() {
        XCTAssertEqual(BaseFace.derive(mode: .live, stage: nil), .live)
        XCTAssertEqual(BaseFace.derive(mode: .live, stage: .land), .arrive)
        XCTAssertEqual(BaseFace.derive(mode: .live, stage: .settle), .arrive)
        XCTAssertEqual(BaseFace.derive(mode: .live, stage: .leave), .recall)
        XCTAssertEqual(BaseFace.derive(mode: .plan, stage: nil), .plan)
    }

    /// Visa ring three-state (decision C): compliance `state()` is nil until an
    /// entry date is confirmed → the header shows the "Set entry" CTA instead
    /// of a ring. Once entry date + length are set, `state()` returns a ring.
    func testComplianceStateGatesVisaRing() {
        let prefs = UserPreferences()

        // Unset → no state → CTA branch.
        prefs.visaEntryDate = nil
        prefs.visaLengthDays = nil
        XCTAssertNil(ComplianceService(preferences: prefs).state(),
                     "no entry date → nil state → Set-entry CTA")

        // Confirmed → state exists → ring branch. Entry 10 calendar days ago
        // means daysStayed = 11 (entry day counts as day 1), so a 30-day visa
        // leaves 30 - 11 = 19.
        prefs.visaEntryDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())
        prefs.visaLengthDays = 30
        let state = ComplianceService(preferences: prefs).state()
        XCTAssertNotNil(state, "entry date + length → ring state")
        XCTAssertEqual(state?.visaDaysRemaining, 19,
                       "30-day visa, 11 days stayed (entry day = day 1) → 19 remaining")
    }
}

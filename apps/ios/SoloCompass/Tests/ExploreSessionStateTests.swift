import XCTest
import CoreLocation
@testable import SoloCompass

/// Tests for ExploreSession derivation + the phase(from:) mapping.
/// Guards the state-machine contract the overlay UI depends on:
///   • `.idle` = no chrome
///   • `.active` = pill + Cancel + dim
///   • `.handoff` = result card
///   • `.cancelled` = kept banner
///
/// Focused, no SwiftData / no XCUIApplication — pure derived-state checks.
@MainActor
final class ExploreSessionStateTests: XCTestCase {

    // MARK: - Phase mapping

    func testProgressIdleMapsToScanning() {
        // Rationale: session enters .idle briefly on entry before first
        // .scanning arrives; the pill should show "Scanning" not blank.
        XCTAssertEqual(MapViewModel.phase(from: .idle), .scanning)
    }

    func testMultiRingScanningMapsToScanning() {
        XCTAssertEqual(
            MapViewModel.phase(from: .multiRingScanning(ringsDone: 2, totalRings: 4)),
            .scanning
        )
    }

    func testScanningMapsToScanning() {
        XCTAssertEqual(MapViewModel.phase(from: .scanning(radiusKm: 5)), .scanning)
    }

    func testExpandingMapsToWidening() {
        XCTAssertEqual(MapViewModel.phase(from: .expanding(toRadiusKm: 25)), .widening)
    }

    func testSynthesizingMapsToSynthesizing() {
        XCTAssertEqual(MapViewModel.phase(from: .synthesizing(poiCount: 47)), .synthesizing)
    }

    // MARK: - isActive semantics

    func testIdleIsNotActive() {
        let s = ExploreSession(state: .idle)
        XCTAssertFalse(s.isActive)
    }

    func testActiveIsActive() {
        let s = ExploreSession(state: .active(
            phase: .scanning,
            radiusMeters: 3000,
            anchor: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            addedCount: 0,
            verifiedCount: 0
        ))
        XCTAssertTrue(s.isActive)
    }

    func testHandoffIsActive() {
        let s = ExploreSession(state: .handoff(.init(
            addedCount: 7, verifiedCount: 3, finalRadiusKm: 3,
            cityName: "Futian", addedIds: [], canExpand: true
        )))
        XCTAssertTrue(s.isActive)
    }

    func testCancelledIsActive() {
        // .cancelled is "active" for UI purposes — the kept banner still
        // needs a stage, even if the scan itself is over.
        let s = ExploreSession(state: .cancelled(kept: 4))
        XCTAssertTrue(s.isActive)
    }

    // MARK: - handoffResult accessor

    func testHandoffResultOnlyOnHandoff() {
        let idle = ExploreSession(state: .idle)
        XCTAssertNil(idle.handoffResult)

        let active = ExploreSession(state: .active(
            phase: .synthesizing, radiusMeters: 6000,
            anchor: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            addedCount: 5, verifiedCount: 2
        ))
        XCTAssertNil(active.handoffResult)

        let handoff = ExploreSession.HandoffResult(
            addedCount: 7, verifiedCount: 3, finalRadiusKm: 3,
            cityName: "Futian", addedIds: ["a", "b"], canExpand: true
        )
        let s = ExploreSession(state: .handoff(handoff))
        XCTAssertEqual(s.handoffResult, handoff)
    }

    // MARK: - Equality edge cases

    func testActiveEqualityRespectsAnchorCoord() {
        let a = ExploreSession(state: .active(
            phase: .scanning, radiusMeters: 3000,
            anchor: CLLocationCoordinate2D(latitude: 1.0, longitude: 2.0),
            addedCount: 0, verifiedCount: 0
        ))
        let b = ExploreSession(state: .active(
            phase: .scanning, radiusMeters: 3000,
            anchor: CLLocationCoordinate2D(latitude: 1.0, longitude: 2.0),
            addedCount: 0, verifiedCount: 0
        ))
        let c = ExploreSession(state: .active(
            phase: .scanning, radiusMeters: 3000,
            anchor: CLLocationCoordinate2D(latitude: 1.1, longitude: 2.0),  // differ
            addedCount: 0, verifiedCount: 0
        ))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Pill localization keys are stable

    /// Regression guard: if a phase adds a variant, the localization key
    /// map must extend too — otherwise the overlay renders an empty pill.
    func testAllPhasesHaveLocalizationKey() {
        for phase in [ExploreSession.Phase.scanning, .verifying, .synthesizing, .widening] {
            XCTAssertTrue(
                phase.pillLocalizationKey.hasPrefix("exploreMode.pill."),
                "phase \(phase) missing pill key"
            )
            // Also make sure the key resolves to a non-key fallback in en.
            let resolved = NSLocalizedString(phase.pillLocalizationKey, comment: "")
            XCTAssertNotEqual(resolved, phase.pillLocalizationKey,
                              "key \(phase.pillLocalizationKey) not localized")
        }
    }
}

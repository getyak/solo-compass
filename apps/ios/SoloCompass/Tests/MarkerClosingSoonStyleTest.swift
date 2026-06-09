import XCTest
import SwiftUI
@testable import SoloCompass

// MARK: - US-049: Map marker escalates to amber when a best-now window closes soon

/// Verifies that a `bestNow` map pin adopts the shared "closing soon" amber
/// treatment once its window has ≤ 45 minutes left, so the map conveys the same
/// urgency the cards / Nearby row / detail sheet / Saved list already show via
/// `BestNowChipState`. Before this, every best-now pin glowed the same gold
/// whether its window had three hours or eight minutes left — hiding the one
/// pin a traveler scanning the map most needs to reach right now.
///
/// `MarkerIconView` exposes the escalation through pure, render-free hooks:
///   - `showsClosingSoon` — the predicate that flips the pulse / fill / glow to
///     amber and shows the alarm-clock badge (true only for a high-confidence
///     best-now pin whose `closingSoon` flag is set);
///   - `accessibilityIdentifier` — gains a `.closingsoon` suffix when it fires,
///     giving a stable way to assert the style differs without rendering;
///   - `bestNowTint` is private, so we assert behaviour through the two hooks
///     above plus the shared amber constant the map and cards both reference.
///
/// Run with:
///   xcodebuild test -only-testing:SoloCompassTests/MarkerClosingSoonStyleTest
final class MarkerClosingSoonStyleTest: XCTestCase {

    // MARK: - Marker view: style changes with the closing-soon flag

    /// A best-now marker must look different when closing soon vs. not — the
    /// whole point of the escalation. We assert via both the predicate and the
    /// identifier suffix.
    func testBestNowMarkerStyleChangesWhenClosingSoon() {
        let calm    = MarkerIconView(category: .coffee, state: .bestNow, confidenceLevel: 4, closingSoon: false)
        let closing = MarkerIconView(category: .coffee, state: .bestNow, confidenceLevel: 4, closingSoon: true)

        XCTAssertFalse(calm.showsClosingSoon, "Not closing soon → calm gold treatment")
        XCTAssertTrue(closing.showsClosingSoon, "Closing soon → best-now pin escalates to amber")

        XCTAssertNotEqual(
            calm.accessibilityIdentifier,
            closing.accessibilityIdentifier,
            "Marker identifier must differ between calm and closing-soon so the style change is observable"
        )
        XCTAssertFalse(
            calm.accessibilityIdentifier.hasSuffix(".closingsoon"),
            "Calm marker must not carry '.closingsoon', got: \(calm.accessibilityIdentifier)"
        )
        XCTAssertTrue(
            closing.accessibilityIdentifier.hasSuffix(".closingsoon"),
            "Closing-soon best-now marker should end with '.closingsoon', got: \(closing.accessibilityIdentifier)"
        )
    }

    /// The escalation is scoped to best-now pins. A non-best-now marker must
    /// look identical regardless of the closing-soon flag (it can never be
    /// "best now, closing soon").
    func testNonBestNowMarkerUnaffectedByClosingSoon() {
        let off = MarkerIconView(category: .food, state: .favorited, confidenceLevel: 4, closingSoon: false)
        let on  = MarkerIconView(category: .food, state: .favorited, confidenceLevel: 4, closingSoon: true)

        XCTAssertFalse(off.showsClosingSoon)
        XCTAssertFalse(on.showsClosingSoon, "Non-best-now markers never escalate to closing-soon")
        XCTAssertEqual(
            off.accessibilityIdentifier,
            on.accessibilityIdentifier,
            "Non-best-now markers must be unchanged by the closing-soon flag"
        )
    }

    /// Low-confidence (AI-guessed) best-now pins don't earn the urgency cue,
    /// mirroring the existing gold pulse-ring and Now-sync suppression — we
    /// don't want tentative entries imitating verified urgency.
    func testLowConfidenceBestNowMarkerHasNoClosingSoonStyle() {
        let on = MarkerIconView(category: .coffee, state: .bestNow, confidenceLevel: 1, closingSoon: true)
        XCTAssertFalse(
            on.showsClosingSoon,
            "Low-confidence best-now pins must not show the closing-soon escalation"
        )
        XCTAssertFalse(on.accessibilityIdentifier.hasSuffix(".closingsoon"))
    }

    /// `closingSoon` must default to false for source compatibility with every
    /// existing call site (the map only opts in for pins that are closing soon).
    func testClosingSoonDefaultsToFalse() {
        let marker = MarkerIconView(category: .coffee, state: .bestNow, confidenceLevel: 4)
        XCTAssertFalse(marker.showsClosingSoon, "closingSoon must default to false")
    }

    /// The map's amber must be the *same* amber every other surface uses, so the
    /// closing-soon cue reads identically on the pin, the chip, and the card.
    func testMapClosingSoonAmberMatchesSharedChipAmber() {
        XCTAssertEqual(
            MarkerIconView.closingSoonAmber,
            BestNowChipState.amber,
            "The map's closing-soon amber must equal BestNowChipState.amber (#F59E0B) so all surfaces agree"
        )
    }

    // MARK: - Closing-soon and Now-sync compose independently

    /// A best-now pin can be both closing soon *and* highlighted by the Now
    /// filter at once; the two cues are orthogonal and both fragments must show.
    func testClosingSoonAndNowSyncCompose() {
        let both = MarkerIconView(
            category: .coffee,
            state: .bestNow,
            confidenceLevel: 4,
            nowFilterActive: true,
            closingSoon: true
        )
        XCTAssertTrue(both.showsClosingSoon)
        XCTAssertTrue(both.showsNowSyncRing)
        XCTAssertTrue(both.accessibilityIdentifier.contains(".nowsync"))
        XCTAssertTrue(both.accessibilityIdentifier.hasSuffix(".closingsoon"))
    }

    // MARK: - End-to-end: a real closing-soon window drives the style

    /// The map computes `closingSoon` via `BestNowChipState.resolve(for:at:)`.
    /// Build a fixture whose window ends ~20 min out (well under the 45-min
    /// threshold) and confirm the resolved flag lights up the marker — the exact
    /// wiring `mapLayer` performs with `closingSoon: isClosingSoon`.
    func testResolvedClosingSoonWindowLightsUpMarkerEndToEnd() {
        // Pin a deterministic instant: 20 minutes before the top of an hour, so
        // the active window (this hour) has exactly ~20 min left.
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 10
        comps.minute = 40
        comps.second = 0
        guard let now = cal.date(from: comps) else {
            return XCTFail("Could not build a deterministic test instant")
        }

        let closingExp = Self.makeBestNowExperience(startHour: 10, endHour: 11)
        let calmExp = Self.makeBestNowExperience(startHour: 8, endHour: 23) // many hours left

        let closingState = BestNowChipState.resolve(for: closingExp, at: now)
        let calmState = BestNowChipState.resolve(for: calmExp, at: now)

        XCTAssertTrue(closingState.isClosingSoon, "~20 min left must read as closing soon")
        XCTAssertFalse(calmState.isClosingSoon, "Hours left must not read as closing soon")

        let closingMarker = MarkerIconView(
            category: closingExp.category,
            state: .bestNow,
            confidenceLevel: closingExp.confidence.level,
            closingSoon: closingState.isClosingSoon
        )
        let calmMarker = MarkerIconView(
            category: calmExp.category,
            state: .bestNow,
            confidenceLevel: calmExp.confidence.level,
            closingSoon: calmState.isClosingSoon
        )

        XCTAssertTrue(closingMarker.showsClosingSoon, "A window closing in ~20 min must light the pin amber")
        XCTAssertFalse(calmMarker.showsClosingSoon, "A window with hours left must stay calm gold")
    }

    // MARK: - Fixtures

    /// A high-confidence best-now café whose `bestTimes` window spans the given
    /// hours. Mirrors the minimal fixture shape used by `FilterNowMapSyncTest`.
    private static func makeBestNowExperience(startHour: Int, endHour: Int) -> Experience {
        let now = Date()
        return Experience(
            id: "closing_soon_fixture_\(startHour)_\(endHour)",
            title: "Closing-Soon Café",
            oneLiner: "Closing-soon fixture",
            whyItMatters: "Closing-soon highlight fixture",
            category: .coffee,
            location: ExperienceLocation(coordinates: [98.99, 18.79], cityCode: "cmi"),
            bestTimes: [TimeWindow(startHour: startHour, endHour: endHour)],
            durationMinutes: .init(min: 30, max: 60),
            howTo: [],
            realInconveniences: [],
            soloScore: SoloScore(
                overall: 5,
                breakdown: .init(
                    seatingFriendly: 7, soloPatronRatio: 7, staffPressure: 7,
                    soloPortioning: 7, ambianceFit: 7, safety: 7
                ),
                basedOnCount: 1
            ),
            sources: [InformationSource(type: .user, attribution: "test", verifiedAt: now)],
            confidence: Confidence(
                level: 4,
                lastVerifiedAt: now,
                reason: "Test fixture",
                signals: .init(aiScrapeAgeDays: 1, passiveGpsHits30d: 0, activeReports30d: 0, trustedVerifications: 0)
            ),
            nearbyExperienceIds: [],
            stats: .init(completionCount: 0, averageRating: 0),
            status: .active,
            createdAt: now,
            updatedAt: now
        )
    }
}

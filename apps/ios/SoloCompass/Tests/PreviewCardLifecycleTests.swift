import XCTest
@testable import SoloCompass

/// Lifecycle tests for the floating preview card that sits above the
/// BottomInfoSheet. The card's on-screen visibility in `CompassMapView` is
/// gated purely on derived state:
///
///     selectedExperience != nil && !isShowingDetail
///
/// Tap-vs-long-press model — the dismiss destination depends on how detail was
/// reached (`MapViewModel.DetailEntrySource`):
///   • TAP a card/pin (`openExperienceDetail`) jumps straight to detail as
///     `.listTap` — `selectedExperience` is set AND `isShowingDetail = true`;
///     backing out CLEARS the selection → clean list, no floating card left over;
///   • LONG-PRESS a card/pin (`selectExperience`) floats the quick preview card
///     as `.mapPeek` — it does NOT open detail;
///   • the preview card's expand action opens the detail sheet above the peek;
///     backing out FALLS BACK to that preview card (selection retained), because
///     detail is a layer above a card the user deliberately summoned;
///   • the card's own dismiss (clearSelection) returns to the bare map and
///     resets the entry source.
///
/// P3 regression guard for the "退出详情后悬窗残留 / Starbucks card floating over
/// the list" report: a list-tap dismiss must NOT leave a preview card hovering
/// over the list, while the long-press peek fall-back stays intact.
@MainActor
final class PreviewCardLifecycleTests: XCTestCase {

    private func makeViewModel() -> MapViewModel {
        MapViewModel(
            locationService: LocationService(),
            experienceService: ExperienceService(),
            aiService: AIService(),
            preferences: UserPreferences()
        )
    }

    /// Mirrors the `if let selected = viewModel.selectedExperience,
    /// !viewModel.isShowingDetail` guard in CompassMapView.
    private func cardIsFloating(_ vm: MapViewModel) -> Bool {
        vm.selectedExperience != nil && !vm.isShowingDetail
    }

    private func firstExperience(_ vm: MapViewModel) throws -> Experience {
        try XCTUnwrap(vm.visibleExperiences.first, "seed expected ≥1 experience")
    }

    // MARK: - Long-press path: selectExperience floats the card, never opens detail

    func testSelectExperienceFloatsCardWithoutOpeningDetail() throws {
        let vm = makeViewModel()
        let exp = try firstExperience(vm)

        vm.selectExperience(exp)             // long-press path
        XCTAssertTrue(cardIsFloating(vm),
                      "long-pressing an experience must float the preview card")
        XCTAssertFalse(vm.isShowingDetail,
                       "long-press must NOT open the detail sheet — it previews")
    }

    // MARK: - Tap path: openExperienceDetail jumps straight to detail

    func testOpenExperienceDetailJumpsStraightToDetail() throws {
        let vm = makeViewModel()
        let exp = try firstExperience(vm)

        vm.openExperienceDetail(exp)         // tap path
        XCTAssertEqual(vm.selectedExperience?.id, exp.id,
                       "tapping must set the selection so back-out lands on the card")
        XCTAssertTrue(vm.isShowingDetail,
                      "tapping a card/pin must open the detail sheet directly")
        XCTAssertFalse(cardIsFloating(vm),
                       "the preview card must NOT float on a tap — detail is up")
    }

    // MARK: - List/pin tap → back-out returns to a CLEAN list (no floating card)

    /// P3 regression: a Nearby/pin *tap* opens detail as `.listTap`; backing out
    /// must clear the selection so no preview card is left hovering over the list
    /// ("Starbucks card floating above the list" / 退出详情后悬窗残留). This is the
    /// listTap ≠ mapPeek distinction — a tap has no card underneath to fall back
    /// to, unlike the long-press peek path below.
    func testListTapDetailThenDismissClearsSelection() throws {
        let vm = makeViewModel()
        let exp = try firstExperience(vm)

        vm.openExperienceDetail(exp)         // list/pin tap → detail (.listTap)
        XCTAssertEqual(vm.detailEntrySource, .listTap,
                       "a tap into detail must record the listTap source")
        vm.dismissDetail()                   // back out of detail
        XCTAssertNil(vm.selectedExperience,
                     "dismissing a list-tapped detail must clear selection — no floating card")
        XCTAssertFalse(cardIsFloating(vm),
                       "no preview card may hover over the clean list after a list-tap dismiss")
        XCTAssertFalse(vm.isShowingDetail)
    }

    // MARK: - Long-press peek → card → detail → back lands on the card again

    /// Approach C: long-press floats the preview card (`.mapPeek`), the card's
    /// expand opens detail *above* it, and backing out peels only the detail
    /// layer — the deliberately-summoned card returns, selection retained.
    func testMapPeekExpandThenDismissDetailFallsBackToCard() throws {
        let vm = makeViewModel()
        let exp = try firstExperience(vm)

        vm.selectExperience(exp)             // long-press peek → card up (.mapPeek)
        XCTAssertEqual(vm.detailEntrySource, .mapPeek,
                       "long-press peek must record the mapPeek source")
        vm.isShowingDetail = true            // onExpand → detail
        XCTAssertFalse(cardIsFloating(vm), "card hidden behind detail")

        vm.dismissDetail()                   // back out of detail
        XCTAssertTrue(cardIsFloating(vm),
                      "dismissing a peek-expanded detail must fall back to the preview card")
        XCTAssertEqual(vm.selectedExperience?.id, exp.id,
                       "selection is retained on a mapPeek detail dismiss")
    }

    // MARK: - Source resets to mapPeek after a full clear

    /// A subsequent long-press peek must not inherit a stale `.listTap` source
    /// from a prior tap — `clearSelection` resets it so the peek → expand →
    /// dismiss fall-back keeps working.
    func testClearSelectionResetsEntrySourceToMapPeek() throws {
        let vm = makeViewModel()
        let exp = try firstExperience(vm)

        vm.openExperienceDetail(exp)         // .listTap
        vm.clearSelection()
        XCTAssertEqual(vm.detailEntrySource, .mapPeek,
                       "clearSelection must reset the entry source to the peek default")
    }

    // MARK: - Card dismiss is the only full exit to the bare map

    func testClearSelectionReturnsToBareMap() throws {
        let vm = makeViewModel()
        let exp = try firstExperience(vm)

        vm.selectExperience(exp)
        vm.clearSelection()                  // the card's own ⨯ / swipe-down
        XCTAssertFalse(cardIsFloating(vm), "card gone")
        XCTAssertNil(vm.selectedExperience, "selection fully cleared")
        XCTAssertFalse(vm.isShowingDetail)
    }

    // MARK: - In-detail switch keeps detail open on the new experience

    func testInDetailSwitchStaysInDetailOnNewExperience() throws {
        let vm = makeViewModel()
        let experiences = vm.visibleExperiences
        try XCTSkipIf(experiences.count < 2, "needs ≥2 seeds to switch between")
        let first = experiences[0]
        let second = experiences[1]

        vm.selectExperience(first)
        vm.isShowingDetail = true            // in detail on `first`

        // In-detail "nearby" tap → selectExperience(second), detail stays up.
        vm.selectExperience(second)
        XCTAssertEqual(vm.selectedExperience?.id, second.id,
                       "in-detail switch must re-point the selection")
        XCTAssertTrue(vm.isShowingDetail,
                      "switching inside detail keeps the detail sheet open")
        XCTAssertFalse(cardIsFloating(vm),
                       "the floating card must not flash during an in-detail switch")
    }
}

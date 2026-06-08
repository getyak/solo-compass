import XCTest
@testable import SoloCompass

/// Lifecycle tests for the floating preview card that sits above the
/// BottomInfoSheet. The card's on-screen visibility in `CompassMapView` is
/// gated purely on derived state:
///
///     selectedExperience != nil && !isShowingDetail
///
/// Tap-vs-long-press model (all card/pin entry points behave the same):
///   • TAP a card/pin (`openExperienceDetail`) jumps straight to the detail
///     sheet — `selectedExperience` is set AND `isShowingDetail = true`;
///   • LONG-PRESS a card/pin (`selectExperience`) floats the quick preview card
///     instead — it does NOT open detail;
///   • the preview card's expand action opens the detail sheet
///     (isShowingDetail = true);
///   • backing out of detail (dismissDetail) FALLS BACK to the preview card —
///     selection is retained, because detail is a layer above the preview;
///   • the card's own dismiss (clearSelection) is the only thing that returns
///     to the bare map.
///
/// Regression guard for the "退出详情后悬窗残留" report: backing out of detail
/// lands on the preview card (selection retained), and `clearSelection` gives a
/// clean exit to the bare map.
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

    // MARK: - Tap → back-out falls back to the preview card

    func testOpenDetailThenDismissFallsBackToCard() throws {
        let vm = makeViewModel()
        let exp = try firstExperience(vm)

        vm.openExperienceDetail(exp)         // tap → detail
        vm.dismissDetail()                   // back out of detail
        XCTAssertTrue(cardIsFloating(vm),
                      "backing out of a tapped detail still lands on the card")
        XCTAssertEqual(vm.selectedExperience?.id, exp.id,
                       "selection retained after dismissing a tapped detail")
    }

    // MARK: - Card → detail → back lands on the card again

    func testExpandThenDismissDetailFallsBackToCard() throws {
        let vm = makeViewModel()
        let exp = try firstExperience(vm)

        vm.selectExperience(exp)             // card up
        vm.isShowingDetail = true            // onExpand → detail
        XCTAssertFalse(cardIsFloating(vm), "card hidden behind detail")

        vm.dismissDetail()                   // back out of detail
        XCTAssertTrue(cardIsFloating(vm),
                      "dismissing detail must fall back to the preview card")
        XCTAssertEqual(vm.selectedExperience?.id, exp.id,
                       "selection is retained on detail dismiss")
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

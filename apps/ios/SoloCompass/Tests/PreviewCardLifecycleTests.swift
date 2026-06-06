import XCTest
@testable import SoloCompass

/// Lifecycle tests for the floating preview card that sits above the
/// BottomInfoSheet. The card's on-screen visibility in `CompassMapView` is
/// gated purely on derived state:
///
///     selectedExperience != nil && !isShowingDetail
///
/// Unified-preview model (all entry points behave the same):
///   • selecting an experience (map pin, Nearby row, favorites) floats the
///     preview card — it does NOT jump straight to detail;
///   • the card's expand action opens the detail sheet (isShowingDetail = true);
///   • backing out of detail (dismissDetail) FALLS BACK to the preview card —
///     selection is retained, because detail is a layer above the preview;
///   • the card's own dismiss (clearSelection) is the only thing that returns
///     to the bare map.
///
/// Regression guard for the "退出详情后悬窗残留" report: the original surprise
/// was that a list row skipped the card on the way in but the card popped up on
/// the way out. Now the card is consistently present on both legs, so the
/// return is expected rather than jarring — and `clearSelection` gives a clean
/// exit.
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

    // MARK: - Unified entry: selecting floats the card, never auto-opens detail

    func testSelectExperienceFloatsCardWithoutOpeningDetail() throws {
        let vm = makeViewModel()
        let exp = try firstExperience(vm)

        vm.selectExperience(exp)
        XCTAssertTrue(cardIsFloating(vm),
                      "selecting an experience must float the preview card")
        XCTAssertFalse(vm.isShowingDetail,
                       "selecting must NOT auto-open the detail sheet — "
                       + "every entry point previews first")
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

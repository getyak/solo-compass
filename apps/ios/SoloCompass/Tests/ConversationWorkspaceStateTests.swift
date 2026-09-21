import XCTest
import SwiftUI
@testable import SoloCompass

/// Behavioural coverage for the conversation workspace controller — the state
/// that keeps the map, chat and discovery as one continuous scene. These are
/// pure-state assertions (no source-string mirrors) so a regression in the
/// transitions, drag projection, keyboard return or scroll bookkeeping fails a
/// real test.
@MainActor
final class ConversationWorkspaceStateTests: XCTestCase {

    // MARK: - Default entry

    func testDefaultEntryLeavesMapVisibleUntilAnExplicitAsk() {
        let state = ConversationWorkspaceState()
        XCTAssertEqual(state.surface, .map)
        XCTAssertEqual(state.detent, .collapsed)
        XCTAssertFalse(state.showsConversation)
        XCTAssertEqual(
            state.targetPanelHeight(containerHeight: 800),
            ConversationWorkspaceState.Metrics.collapsedHeight,
            accuracy: 0.5
        )
        state.autoExpandWhileWorking()
        XCTAssertEqual(state.surface, .map, "Background activity must not take over launch")
        state.requestPrompt("Find a quiet cafe")
        XCTAssertEqual(state.surface, .ask)
        XCTAssertEqual(state.detent, .conversation)
        XCTAssertEqual(state.consumePendingPrompt()?.text, "Find a quiet cafe")
    }

    // MARK: - Geometry

    func testPanelHeightFractions() {
        XCTAssertEqual(
            ConversationWorkspaceState.panelHeight(for: .conversation, containerHeight: 800),
            624, accuracy: 0.5
        )
        XCTAssertEqual(
            ConversationWorkspaceState.panelHeight(for: .expanded, containerHeight: 800),
            760, accuracy: 0.5
        )
        XCTAssertEqual(
            ConversationWorkspaceState.panelHeight(for: .collapsed, containerHeight: 800),
            ConversationWorkspaceState.Metrics.collapsedHeight, accuracy: 0.5
        )
    }

    func testConversationDetentLeavesTopMapChromeOnShortScreens() {
        let height = ConversationWorkspaceState.panelHeight(for: .conversation, containerHeight: 300)
        XCTAssertLessThanOrEqual(
            height, 300 - ConversationWorkspaceState.Metrics.minTopClearance,
            "On a short container the conversation detent stops short of the map chrome"
        )
        XCTAssertGreaterThan(height, ConversationWorkspaceState.Metrics.collapsedHeight)
    }

    func testDraggedHeightInsideBoundsIsUnchanged() {
        XCTAssertEqual(
            ConversationWorkspaceState.clampDraggedHeight(500, containerHeight: 800),
            500, accuracy: 0.01
        )
    }

    func testDraggedHeightRubberBandsPastTheEdges() {
        let maxHeight = 800 * ConversationWorkspaceState.Metrics.expandedFraction
        let overshoot = ConversationWorkspaceState.clampDraggedHeight(1400, containerHeight: 800)
        XCTAssertGreaterThan(overshoot, maxHeight, "The panel still follows the finger past the edge")
        XCTAssertLessThan(overshoot, 1400, "…but the excess is damped, not 1:1")

        let undershoot = ConversationWorkspaceState.clampDraggedHeight(-500, containerHeight: 800)
        XCTAssertLessThan(undershoot, ConversationWorkspaceState.Metrics.collapsedHeight)
        XCTAssertGreaterThan(undershoot, -500, "Pulling below the bar is damped too")
    }

    // MARK: - Snap (current → dragged → projected)

    func testSnapWithoutProjectionReturnsCurrent() {
        XCTAssertEqual(
            ConversationWorkspaceState.snapDetent(
                current: .conversation,
                proposedHeight: 600,
                projectedHeight: 600,
                containerHeight: 800
            ),
            .conversation
        )
    }

    func testSnapFollowsTheProjectionToTheNeighbouringDetent() {
        XCTAssertEqual(
            ConversationWorkspaceState.snapDetent(
                current: .conversation,
                proposedHeight: 700,
                projectedHeight: 760,
                containerHeight: 800
            ),
            .expanded,
            "An upward projection into the expanded band commits expanded"
        )
        XCTAssertEqual(
            ConversationWorkspaceState.snapDetent(
                current: .expanded,
                proposedHeight: 620,
                projectedHeight: 590,
                containerHeight: 800
            ),
            .conversation,
            "A downward projection settles on conversation"
        )
    }

    func testOneFlickCannotSkipADetent() {
        XCTAssertEqual(
            ConversationWorkspaceState.snapDetent(
                current: .collapsed,
                proposedHeight: 130,
                projectedHeight: 100_000,
                containerHeight: 800
            ),
            .conversation,
            "From the map a flick opens to conversation, not straight past it"
        )
        XCTAssertEqual(
            ConversationWorkspaceState.snapDetent(
                current: .conversation,
                proposedHeight: 700,
                projectedHeight: 100_000,
                containerHeight: 800
            ),
            .expanded
        )
    }

    // MARK: - Surface / detent transitions

    func testSurfaceAndDetentStayInSync() {
        let state = ConversationWorkspaceState()
        state.selectSurface(.ask)
        XCTAssertTrue(state.selectSurface(.map))
        XCTAssertEqual(state.surface, .map)
        XCTAssertEqual(state.detent, .collapsed, "Selecting the map collapses the panel")

        XCTAssertTrue(state.selectSurface(.discover))
        XCTAssertEqual(state.surface, .discover)
        XCTAssertEqual(state.detent, .expanded, "Discovery opens tall enough to browse")

        XCTAssertTrue(state.selectSurface(.ask))
        XCTAssertEqual(state.surface, .ask)
        XCTAssertEqual(state.detent, .conversation, "Returning to the chat restores its height")
    }

    func testNoOpSurfaceSelectionReportsNoChange() {
        let state = ConversationWorkspaceState()
        XCTAssertFalse(state.selectSurface(.map), "Selecting the active surface is a no-op")
        XCTAssertEqual(state.manualDetentRevision, 0, "…and does not bump the revision")
    }

    func testCollapsingByDetentSelectsMapTab() {
        let state = ConversationWorkspaceState()
        state.selectSurface(.ask)
        XCTAssertTrue(state.selectDetent(.collapsed))
        XCTAssertEqual(state.surface, .map)
        XCTAssertTrue(state.selectDetent(.expanded))
        XCTAssertEqual(state.surface, .ask, "Expanding from the map returns to the chat tab")
        XCTAssertFalse(state.selectDetent(.expanded), "Re-committing the same detent is a no-op")
    }

    // MARK: - Auto-expansion

    func testAutoExpandOnlyForUnpinnedChat() {
        let state = ConversationWorkspaceState()
        state.selectSurface(.ask)
        state.autoExpandWhileWorking()
        XCTAssertEqual(state.detent, .expanded, "Unpinned chat grows to room the reply")

        let pinned = ConversationWorkspaceState()
        pinned.selectSurface(.map)
        pinned.autoExpandWhileWorking()
        XCTAssertEqual(pinned.detent, .collapsed, "The user's map view must never be overridden")
        XCTAssertEqual(pinned.surface, .map)
    }

    func testAutoExpandLeavesAMapViewAlone() {
        let state = ConversationWorkspaceState()
        state.selectSurface(.map)
        state.autoExpandWhileWorking()
        XCTAssertEqual(state.detent, .collapsed, "A chosen map view is never overridden")
        XCTAssertEqual(state.surface, .map)

        // Discovery is also left alone; only the chat surface expands.
        let discovering = ConversationWorkspaceState()
        discovering.selectSurface(.discover)
        discovering.autoExpandWhileWorking()
        XCTAssertEqual(discovering.surface, .discover)
    }

    // MARK: - Keyboard return

    func testKeyboardExpandsAndRestoresPreviousDetent() {
        let state = ConversationWorkspaceState()
        state.selectSurface(.ask)
        let snapshot = state.expandForKeyboard()
        XCTAssertEqual(snapshot.detent, .conversation)
        XCTAssertEqual(state.detent, .expanded)
        state.restoreAfterKeyboard(snapshot)
        XCTAssertEqual(state.detent, .conversation)
    }

    func testManualChoiceDuringTypingWinsOverKeyboardRestore() {
        let state = ConversationWorkspaceState()
        state.selectSurface(.ask)
        let snapshot = state.expandForKeyboard()
        // The user pins a different detent while the keyboard is up.
        state.selectDetent(.conversation)
        state.restoreAfterKeyboard(snapshot)
        XCTAssertEqual(state.detent, .conversation, "The manual choice after focus is preserved")
        XCTAssertGreaterThan(state.manualDetentRevision, snapshot.revision)
    }

    func testKeyboardRestoreIsNotFooledByAnUnrelatedManualAction() {
        let state = ConversationWorkspaceState()
        state.selectSurface(.ask)
        let snapshot = state.expandForKeyboard()
        // A manual surface change bumps the revision even without a detent change.
        state.selectSurface(.discover)
        state.restoreAfterKeyboard(snapshot)
        XCTAssertEqual(state.surface, .discover, "A later manual navigation is not clobbered")
    }

    // MARK: - Draft / attachment preservation

    func testDraftAndAttachmentsSurviveSurfaceSwitches() {
        let state = ConversationWorkspaceState()
        state.selectSurface(.ask)
        state.draftText = "half-written plan"
        state.attachments = [
            LocalAttachment(
                kind: .file,
                fileName: "notes.pdf",
                mimeType: "application/pdf",
                data: Data([0x01, 0x02])
            )
        ]
        state.selectSurface(.map)
        state.selectSurface(.discover)
        state.selectSurface(.ask)
        XCTAssertEqual(state.draftText, "half-written plan")
        XCTAssertEqual(state.attachments.count, 1, "Staged attachments are never dropped by a surface switch")
    }

    // MARK: - Explicit ask channel

    func testExplicitPromptIsDeliveredExactlyOnce() {
        let state = ConversationWorkspaceState()
        state.requestPrompt("  where should I read?  ")
        XCTAssertEqual(state.promptToken, 1)
        XCTAssertEqual(state.surface, .ask, "An explicit ask returns to the chat surface")

        let first = state.consumePendingPrompt()
        XCTAssertEqual(first?.text, "where should I read?")
        XCTAssertNil(state.consumePendingPrompt(), "A consumed ask can never be resubmitted")

        state.requestPrompt("where should I read?")
        XCTAssertEqual(state.promptToken, 2, "An identical repeat still raises a fresh token")
        XCTAssertEqual(state.consumePendingPrompt()?.text, "where should I read?")
    }

    func testEmptyPromptIsIgnored() {
        let state = ConversationWorkspaceState()
        state.requestPrompt("   ")
        XCTAssertEqual(state.promptToken, 0)
        XCTAssertNil(state.consumePendingPrompt())
    }

    func testVoiceStartRaisesFromCollapsedMap() {
        let state = ConversationWorkspaceState()
        state.selectSurface(.map)
        state.requestVoiceStart()
        XCTAssertEqual(state.voiceStartToken, 1)
        XCTAssertEqual(state.surface, .ask)
        XCTAssertEqual(state.detent, .conversation)
    }

    func testHibernationRaisesTokenWithoutChangingSurface() {
        let state = ConversationWorkspaceState()
        state.selectSurface(.ask)
        state.requestHibernation()
        XCTAssertEqual(state.hibernationToken, 1)
        XCTAssertEqual(state.surface, .ask, "Hibernating a modal does not move the surface")
    }

    // MARK: - Scroll intent

    func testSendThenScrollAwayStopsFollowing() {
        let state = ConversationWorkspaceState()
        state.beginFollowing()
        XCTAssertTrue(state.shouldFollowScroll, "A send follows its own reply")

        // The reader scrolls up mid-stream. Follow intent must be cleared so the
        // rest of the token stream cannot keep yanking them down.
        state.noteScrolledAwayFromBottom()
        XCTAssertFalse(state.followStreaming, "Scrolling away clears the explicit follow")
        XCTAssertFalse(state.shouldFollowScroll)
    }

    func testReplyWhileAwaySurfacesReturnToLatestAndDoesNotFollow() {
        let state = ConversationWorkspaceState()
        state.noteScrolledAwayFromBottom()
        XCTAssertFalse(state.isNearBottom)

        state.noteContentArrivedWhileAway()
        XCTAssertTrue(state.showsReturnToLatest)
        XCTAssertFalse(state.shouldFollowScroll, "A reply while reading history must not yank the scroll")

        state.beginFollowing()
        XCTAssertTrue(state.isNearBottom)
        XCTAssertFalse(state.showsReturnToLatest)
        XCTAssertTrue(state.shouldFollowScroll)

        state.endFollowing()
        XCTAssertFalse(state.followStreaming)
    }

    // MARK: - Streaming throttle

    func testThrottleCoalescesRapidRequestsIntoOneFire() async {
        let throttle = ScrollFollowThrottle()
        var fires = 0
        for _ in 0..<6 {
            throttle.request(interval: .milliseconds(40), shouldFollow: { true }, action: { fires += 1 })
        }
        XCTAssertEqual(throttle.scheduleCount, 1, "Only one window is scheduled while one is pending")
        try? await Task.sleep(for: .milliseconds(140))
        XCTAssertEqual(fires, 1)
        XCTAssertEqual(throttle.fireCount, 1)
    }

    func testThrottleRechecksIntentAtExecution() async {
        let throttle = ScrollFollowThrottle()
        var fires = 0
        throttle.request(interval: .milliseconds(40), shouldFollow: { false }, action: { fires += 1 })
        try? await Task.sleep(for: .milliseconds(140))
        XCTAssertEqual(fires, 0, "A reader who scrolled away during the window is not followed")
        XCTAssertEqual(throttle.fireCount, 0)
    }

    func testThrottleSchedulesAgainAfterAWindowCompletes() async {
        let throttle = ScrollFollowThrottle()
        var fires = 0
        throttle.request(interval: .milliseconds(30), shouldFollow: { true }, action: { fires += 1 })
        try? await Task.sleep(for: .milliseconds(90))
        throttle.request(interval: .milliseconds(30), shouldFollow: { true }, action: { fires += 1 })
        try? await Task.sleep(for: .milliseconds(90))
        XCTAssertEqual(fires, 2, "Throttle is trailing-edge, not a one-shot")
        XCTAssertEqual(throttle.scheduleCount, 2)
    }

    func testThrottleCancelDropsPendingAction() async {
        let throttle = ScrollFollowThrottle()
        var fires = 0
        throttle.request(interval: .milliseconds(40), shouldFollow: { true }, action: { fires += 1 })
        throttle.cancel()
        try? await Task.sleep(for: .milliseconds(140))
        XCTAssertEqual(fires, 0)
    }

    // MARK: - Derived presentation

    func testCompactConversationOnlyAtConversationDetent() {
        let state = ConversationWorkspaceState()
        state.selectSurface(.ask)
        XCTAssertTrue(state.isCompactConversation)
        state.selectDetent(.expanded)
        XCTAssertFalse(state.isCompactConversation)
        state.selectDetent(.collapsed)
        XCTAssertFalse(state.isCompactConversation)
    }

    // MARK: - Display sanitization

    func testInternalExperienceMarkersAreSuppressedForDisplay() {
        let raw = "Try [exp:cmi_khao_soi_1974] then [exp_cmi_bookstore_work] → [exp_cmi_nimman_coffee]."
        let clean = ChatSheet.sanitizeForDisplay(raw)
        XCTAssertFalse(clean.contains("[exp"), "Internal reference markers must not leak into visible text")
        XCTAssertTrue(clean.contains("Try"), "Real prose survives")
    }

    func testMarkerOnlySequenceLinesAreDropped() {
        let raw = "[exp:a] → [exp_b]"
        XCTAssertEqual(ChatSheet.sanitizeForDisplay(raw), "")
    }

    func testObservedMarkerChainCollapsesCleanly() {
        // Exact shape observed in a live reply.
        let raw = "**route title** [exp:cmi_khao_soi_1974] → [exp_cmi_bookstore_work] → [exp_cmi_nimman_coffee]."
        let clean = ChatSheet.sanitizeForDisplay(raw)
        XCTAssertEqual(clean, "**route title**.")
        XCTAssertFalse(clean.contains("→"), "No dangling arrows")
        XCTAssertFalse(clean.contains("[exp"), "No opaque ids")
    }

    func testProseArrowsOutsideMarkersArePreserved() {
        let raw = "Head north → then turn left"
        XCTAssertEqual(ChatSheet.sanitizeForDisplay(raw), raw)
    }

    func testNormalUserBracketedTextIsPreserved() {
        let user = "Book [the quiet one] please"
        XCTAssertEqual(ChatSheet.sanitizeForDisplay(user), user)
    }

    // MARK: - Reading anchor

    func testReadingAnchorSurvivesOrdinarySurfaceSwitches() {
        let state = ConversationWorkspaceState()
        state.syncAnchorConversation(id: "chat-1")
        let anchor = UUID()
        state.noteVisibleAnchor(anchor)

        // Leaving to the map and discovery is an ordinary excursion: the row the
        // reader was on must be preserved.
        state.selectSurface(.map)
        state.selectSurface(.discover)
        state.selectSurface(.ask)
        XCTAssertEqual(state.visibleAnchorId, anchor)
        XCTAssertEqual(state.anchorConversationId, "chat-1")
    }

    func testChangingConversationResetsTheReadingAnchor() {
        let state = ConversationWorkspaceState()
        state.syncAnchorConversation(id: "chat-1")
        state.noteVisibleAnchor(UUID())
        // A new chat / restored history record must open fresh, not on a stale row.
        state.syncAnchorConversation(id: "chat-2")
        XCTAssertNil(state.visibleAnchorId)
        XCTAssertEqual(state.anchorConversationId, "chat-2")
    }

    func testSendingClearsTheReadingAnchor() {
        let state = ConversationWorkspaceState()
        state.noteVisibleAnchor(UUID())
        state.beginFollowing()
        XCTAssertNil(state.visibleAnchorId, "An explicit send intentionally follows the bottom")
    }

    func testSoftwareKeyboardSignalIsIdempotent() {
        let state = ConversationWorkspaceState()
        state.setSoftwareKeyboardVisible(true)
        state.setSoftwareKeyboardVisible(true)
        XCTAssertTrue(state.isSoftwareKeyboardVisible)
        state.setSoftwareKeyboardVisible(false)
        XCTAssertFalse(state.isSoftwareKeyboardVisible)
    }

    // MARK: - Accessibility identifiers

    func testWorkspaceAccessibilityIdentifiersAreStable() {
        XCTAssertEqual(WorkspaceAccessibility.panel, "workspace.panel")
        XCTAssertEqual(WorkspaceAccessibility.handle, "workspace.handle")
        XCTAssertEqual(WorkspaceAccessibility.dock, "workspace.dock")
        XCTAssertEqual(WorkspaceAccessibility.composer, "workspace.composer")
        XCTAssertEqual(WorkspaceAccessibility.returnToLatest, "workspace.returnToLatest")
        XCTAssertEqual(WorkspaceAccessibility.dockItem(.map), "workspace.dock.map")
        XCTAssertEqual(WorkspaceAccessibility.dockItem(.ask), "workspace.dock.ask")
        XCTAssertEqual(WorkspaceAccessibility.dockItem(.discover), "workspace.dock.discover")
    }
}

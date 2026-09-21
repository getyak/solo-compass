import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The conversation/discovery panel that floats over the map.
///
/// The workspace and orchestrator retain conversation state while the content
/// switches between chat and discovery. The panel changes its height; MapKit
/// keeps its identity and camera behind it.
///
/// Layout contract (fixes the native R0 "blank collapsed box / dock pushed
/// off-screen" bug): the grabber and the dock are **fixed siblings anchored
/// outside the dynamic content area**. The content sits in the middle band and
/// is clipped there, so no matter how tall its intrinsic content is it can never
/// push the dock out of view. When the panel is collapsed the middle band is
/// nearly zero-height and simply clips away.
///
/// Gesture ownership: the drag lives on the grabber only, through a
/// `@GestureState` so SwiftUI resets it automatically if the gesture is
/// cancelled (rotation, backgrounding, a system takeover). The message
/// `ScrollView` keeps its own vertical scroll and MapKit keeps its pan/zoom, so
/// the three never fight over the same gesture.
@MainActor
struct ConversationPanel<Content: View, Dock: View>: View {
    let workspace: ConversationWorkspaceState
    /// Height of the container the panel floats in — the basis for the
    /// fraction-based detents.
    let containerHeight: CGFloat
    /// Called when a drag release or handle tap commits a new detent.
    let onDetentCommitted: (ConversationWorkspaceState.PanelDetent) -> Void
    private let content: () -> Content
    private let dock: () -> Dock

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Live drag translation. `@GestureState` is reset by SwiftUI whenever the
    /// gesture becomes inactive — including cancellation — so a stuck height is
    /// impossible.
    // Reset is its own transaction: it also runs on cancellation and when the
    // selected detent does not change. No mirrored state can race the reset.
    @GestureState(resetTransaction: Transaction(animation: Motion.settle))
    private var dragTranslation: CGFloat = 0

    /// Grabber band height (also the grabber's ≥44pt hit area).
    static var grabberHeight: CGFloat { 44 }
    /// Space reserved for the dock so the content can never overlap it.
    static var dockHeight: CGFloat { 76 }

    init(
        workspace: ConversationWorkspaceState,
        containerHeight: CGFloat,
        onDetentCommitted: @escaping (ConversationWorkspaceState.PanelDetent) -> Void = { _ in },
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder dock: @escaping () -> Dock
    ) {
        self.workspace = workspace
        self.containerHeight = containerHeight
        self.onDetentCommitted = onDetentCommitted
        self.content = content
        self.dock = dock
    }

    var body: some View {
        let dockReserve = workspace.isSoftwareKeyboardVisible ? 0 : Self.dockHeight
        ZStack(alignment: .top) {
            // Middle band: clipped, so oversized content can never affect the
            // grabber or dock layout.
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, Self.grabberHeight)
                .padding(.bottom, dockReserve)
                .clipped()

            // Fixed top grabber (also the accessible collapse/back action).
            grabber
                .frame(height: Self.grabberHeight)
        }
        .frame(height: liveHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .clipShape(panelShape)
        // The rounded panel fill continues to the physical screen bottom (not
        // just the safe area) so no MapKit strip shows under the home indicator.
        .background(
            panelShape
                .fill(panelBackground)
                .ignoresSafeArea(.container, edges: .bottom)
        )
        .overlay(alignment: .top) {
            panelShape
                .strokeBorder(borderColor, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        // The dock is an overlay (no layout participation) anchored to the
        // panel's bottom, padded clear of the home indicator. It is dropped
        // while the software keyboard is up so the composer sits directly above
        // the keyboard; the grabber still provides collapse.
        .overlay(alignment: .bottom) {
            if !workspace.isSoftwareKeyboardVisible {
                dock()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
        }
        .elevation(Elevation.sheet)
        .animation(reduceMotion ? nil : Motion.settle, value: workspace.detent)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(WorkspaceAccessibility.panel)
    }

    // MARK: - Grabber

    /// The grabber is the *only* drag owner. It is deliberately a large,
    /// accessible control: a visible capsule for sighted users, a ≥44pt hit
    /// area for touch, a tap toggle, and an adjustable action for VoiceOver.
    /// The drag uses a movement threshold so a tap is never swallowed.
    private var grabber: some View {
        Capsule()
            .fill(grabberFill)
            .frame(width: 44, height: 5)
            .frame(maxWidth: .infinity)
            // Explicit ≥44pt frame BEFORE contentShape/gesture so the tappable
            // and draggable rect is 44pt tall, not just the 5pt capsule padded
            // by the parent.
            .frame(height: Self.grabberHeight)
            .contentShape(Rectangle())
            .onTapGesture { toggleDetent() }
            .gesture(grabberDrag)
            .accessibilityElement()
            .accessibilityIdentifier(WorkspaceAccessibility.handle)
            .accessibilityLabel(Text(NSLocalizedString(
                "workspace.handle.a11y",
                comment: "Accessibility label for the conversation panel drag handle"
            )))
            .accessibilityHint(Text(NSLocalizedString(
                "workspace.handle.hint",
                comment: "Accessibility hint: drag or swipe up and down to resize"
            )))
            .accessibilityValue(Text(detentAccessibilityValue))
            .accessibilityAddTraits(.isButton)
            // A real default action (the trait alone is not actionable): a
            // double-tap toggles the panel.
            .accessibilityAction { toggleDetent() }
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    commit(workspace.detent.larger, haptic: true)
                case .decrement:
                    commit(workspace.detent.smaller, haptic: true)
                @unknown default:
                    break
                }
            }
    }

    private var grabberDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($dragTranslation) { value, state, transaction in
                transaction.animation = nil
                state = value.translation.height
            }
            .onEnded { value in
                let committed = workspace.targetPanelHeight(containerHeight: containerHeight)
                let proposed = ConversationWorkspaceState.clampDraggedHeight(
                    committed - value.translation.height,
                    containerHeight: containerHeight
                )
                // `predictedEndTranslation` is a displacement: where the finger
                // was heading, not a velocity.
                let projected = ConversationWorkspaceState.clampDraggedHeight(
                    committed - value.predictedEndTranslation.height,
                    containerHeight: containerHeight
                )
                let next = ConversationWorkspaceState.snapDetent(
                    current: workspace.detent,
                    proposedHeight: proposed,
                    projectedHeight: projected,
                    containerHeight: containerHeight
                )
                commit(next, haptic: true)
            }
    }

    // MARK: - Detent commits

    private func toggleDetent() {
        let next: ConversationWorkspaceState.PanelDetent =
            workspace.detent == .expanded ? .conversation : .expanded
        commit(next, haptic: true)
    }

    private func commit(_ next: ConversationWorkspaceState.PanelDetent, haptic: Bool) {
        let changed = next != workspace.detent
        if changed {
            if reduceMotion {
                workspace.selectDetent(next)
            } else {
                withAnimation(Motion.settle) {
                    workspace.selectDetent(next)
                }
            }
        }
        if haptic && changed {
            #if canImport(UIKit)
            Haptics.selection()
            #endif
        }
        if changed {
            onDetentCommitted(next)
        }
    }

    // MARK: - Rendering

    private var liveHeight: CGFloat {
        guard dragTranslation != 0 else {
            return workspace.targetPanelHeight(containerHeight: containerHeight)
        }
        let committed = workspace.targetPanelHeight(containerHeight: containerHeight)
        return ConversationWorkspaceState.clampDraggedHeight(
            committed - dragTranslation,
            containerHeight: containerHeight
        )
    }

    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Radius.xl,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: Radius.xl,
            style: .continuous
        )
    }

    private var detentAccessibilityValue: String {
        switch workspace.detent {
        case .collapsed:
            return NSLocalizedString("workspace.detent.collapsed", comment: "Panel collapsed onto the map")
        case .conversation:
            return NSLocalizedString("workspace.detent.conversation", comment: "Panel at conversation height")
        case .expanded:
            return NSLocalizedString("workspace.detent.expanded", comment: "Panel expanded")
        }
    }

    private var panelBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [CT.warmSheetDark, Color(.systemBackground)]
                : [CT.bgWarm, CT.surfaceWhite],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var borderColor: Color {
        colorScheme == .dark ? CT.warmBorderDark : CT.borderSubtle
    }

    private var grabberFill: Color {
        colorScheme == .dark ? Color(.separator) : CT.borderDefault
    }
}

#Preview("Panel — conversation") {
    ZStack(alignment: .bottom) {
        Color(.systemTeal).ignoresSafeArea()
        ConversationPanel(
            workspace: ConversationWorkspaceState(),
            containerHeight: 800
        ) {
            Color.clear
        } dock: {
            Color.clear.frame(height: 60)
        }
    }
}

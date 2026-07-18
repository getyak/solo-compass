import SwiftUI

// MARK: - DismissibleBanner
//
// A reusable "drag-to-dismiss" transient banner (undo toasts, check-in prompts).
// It distils the on-device-tuned gesture model from `BottomInfoSheet` /
// `ChatCardStack.ProvisionalCardRow` — the two reference implementations in the
// app — into one modifier so the three hand-rolled copies (FavoritesListView,
// ItineraryListView, PendingCheckInBanner) stop drifting apart.
//
// The three properties an Apple-grade drag-to-dismiss must have (WWDC 2018
// "Designing Fluid Interfaces"), all of which the old copies were missing:
//
//   1. 1:1 tracking — content follows the finger exactly within the pull
//      direction; resistance (rubber-band) appears ONLY past the threshold, not
//      as a blanket `* 0.85` multiplier applied to the whole travel. The old
//      code damped the entire drag, so the banner never quite kept up with the
//      finger.
//   2. Momentum projection — the release decision uses `predictedEndTranslation`
//      (where the flick is *going*), not the raw release-point translation. A
//      quick short flick now dismisses; the old `translation > 80` check ignored
//      velocity, so a fast small flick did nothing and the user had to "drag it
//      far enough".
//   3. Velocity-continuous settle — on commit the banner flies off with a spring
//      (Motion.settle) rather than a fixed `.easeOut(duration: 0.2)`, so there's
//      no seam between the finger's motion and the animation.
//
// Direction is configurable: undo toasts sit at the bottom and dismiss *down*;
// the check-in prompt sits at the top and dismisses *up*.

/// Which way the banner is pulled to dismiss.
enum BannerDismissEdge {
    /// Pulled downward off the bottom of the screen (undo toasts).
    case down
    /// Pulled upward off the top of the screen (check-in prompt).
    case up

    /// Sign of a dismiss-ward translation for this edge (+1 down, -1 up).
    fileprivate var sign: CGFloat { self == .down ? 1 : -1 }
}

extension View {
    /// Makes the view draggable off-screen in `edge` direction to dismiss.
    ///
    /// - Parameters:
    ///   - offset: Bound live drag offset (the caller owns it so the countdown
    ///     bar / pause logic can read it). Non-dismiss-ward pulls are clamped to 0.
    ///   - edge: Which way the banner leaves.
    ///   - threshold: Projected travel (pt) past which a release commits dismiss.
    ///   - isEnabled: When false the gesture is inert (e.g. already confirmed).
    ///   - onCrossThreshold: Fired once each time the *projected* position crosses
    ///     the threshold in either direction — for the "you can let go now" tick.
    ///   - onDragBegan: Fired on the first move of a fresh drag (pause countdown).
    ///   - onDismiss: Committed dismiss (past threshold or fast flick).
    ///   - onCancel: Released below threshold; the banner springs home.
    func dismissibleBanner(
        offset: Binding<CGFloat>,
        edge: BannerDismissEdge,
        threshold: CGFloat = 80,
        isEnabled: Bool = true,
        onCrossThreshold: @escaping (Bool) -> Void = { _ in },
        onDragBegan: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) -> some View {
        modifier(DismissibleBannerModifier(
            offset: offset,
            edge: edge,
            threshold: threshold,
            isEnabled: isEnabled,
            onCrossThreshold: onCrossThreshold,
            onDragBegan: onDragBegan,
            onDismiss: onDismiss,
            onCancel: onCancel
        ))
    }
}

private struct DismissibleBannerModifier: ViewModifier {
    @Binding var offset: CGFloat
    let edge: BannerDismissEdge
    let threshold: CGFloat
    let isEnabled: Bool
    let onCrossThreshold: (Bool) -> Void
    let onDragBegan: () -> Void
    let onDismiss: () -> Void
    let onCancel: () -> Void

    @State private var crossed = false
    @State private var began = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far past `threshold` the banner keeps following before flying off —
    /// the extra travel is rubber-banded so overshoot resists instead of running
    /// away (apple-design §9).
    private static let rubberBandDamping: CGFloat = 0.3

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard isEnabled else { return }
                        if !began {
                            began = true
                            onDragBegan()
                        }
                        // Dismiss-ward travel is positive; ignore the opposite pull.
                        let travel = value.translation.height * edge.sign
                        let dismissWard = max(0, travel)
                        // 1:1 up to the threshold; rubber-band only the overshoot.
                        let followed: CGFloat
                        if dismissWard > threshold {
                            followed = threshold + (dismissWard - threshold) * Self.rubberBandDamping
                        } else {
                            followed = dismissWard
                        }
                        offset = followed * edge.sign

                        // Cross feedback keys off the PROJECTED endpoint so the
                        // "let go now" tick anticipates the flick, not the finger.
                        let projected = value.predictedEndTranslation.height * edge.sign
                        let over = projected > threshold
                        if over != crossed {
                            crossed = over
                            Haptics.selection()
                        }
                    }
                    .onEnded { value in
                        guard isEnabled else { return }
                        began = false
                        crossed = false
                        let projected = value.predictedEndTranslation.height * edge.sign
                        let committed = projected > threshold
                        if committed {
                            Haptics.impact(.soft)
                            // Fly off in the dismiss direction with a settle
                            // spring so the finger's motion continues seamlessly.
                            withAnimation(reduceMotion ? nil : Motion.settle) {
                                offset = 320 * edge.sign
                            }
                            onDismiss()
                        } else {
                            withAnimation(reduceMotion ? nil : Motion.settle) {
                                offset = 0
                            }
                            onCancel()
                        }
                    }
            )
    }
}

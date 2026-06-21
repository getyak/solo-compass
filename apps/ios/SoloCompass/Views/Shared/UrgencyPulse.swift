import SwiftUI

/// Subtle breathing-scale animation applied to UI surfaces that need to convey
/// "you have minutes, not an hour" without strobing — currently used by the
/// "Best now" chip when the window has ≤ `BestNowChipState.urgentThresholdMinutes`
/// left. Pulses between 1.0 and 1.05 over ~1.6s; honors `accessibilityReduceMotion`
/// (no-ops when reduce-motion is on) so it never fights system accessibility.
///
/// Standalone modifier so other surfaces (peek summary, nearby row, route ETA
/// chip) can adopt the same urgency vocabulary without copy-pasting the timer
/// or animation tuning. Keep parameters constant across surfaces — consistency
/// is the whole point.
struct UrgencyPulse: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Bool = false

    func body(content: Content) -> some View {
        let shouldAnimate = active && !reduceMotion
        return content
            .scaleEffect(shouldAnimate && phase ? 1.05 : 1.0)
            .animation(
                shouldAnimate
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: phase
            )
            .onAppear {
                guard shouldAnimate else { return }
                phase = true
            }
            .onChange(of: active) { _, newValue in
                phase = newValue && !reduceMotion
            }
    }
}

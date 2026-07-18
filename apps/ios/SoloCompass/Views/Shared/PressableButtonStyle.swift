import SwiftUI

/// Scales the label down ~8% on press and springs back, giving tappable
/// surfaces a physical, tactile feel. Shared between the filter pills and the
/// chat input bar so the press feedback stays consistent across the app.
public struct PressableButtonStyle: ButtonStyle {
    /// Press-down scale. Default 0.92 matches the filter pills; the send button
    /// passes a slightly punchier value.
    private let pressedScale: CGFloat
    /// Whether to fire a light selection haptic. Default is **off** — the audit
    /// found this style applied to ~34 buttons, of which only 2 opted out, so
    /// the app buzzed on essentially every button *press-down*, including plain
    /// navigation taps. That trains users to ignore all haptics (HIG: reserve
    /// haptics for meaningful commits). Opt in (`haptic: true`) only on genuine
    /// state-change/commit surfaces — a filter toggling, a message sending.
    private let haptic: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(pressedScale: CGFloat = 0.92, haptic: Bool = false) {
        self.pressedScale = pressedScale
        self.haptic = haptic
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Motion.press: near-critically damped (df 0.82) so the button
            // settles crisply like a system control instead of the old df-0.6
            // wobble that overshot on release.
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .animation(reduceMotion ? nil : Motion.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { wasPressed, isPressed in
                // Fire on release (commit), not press-down: the haptic should
                // confirm the action, not merely acknowledge a finger landing.
                if wasPressed && !isPressed && haptic && !reduceMotion {
                    #if canImport(UIKit)
                    Haptics.selection()
                    #endif
                }
            }
    }
}

// MARK: - Preview

#Preview("Tappable Pill") {
    VStack(spacing: 20) {
        Button("Filter Pill") {}
            .buttonStyle(PressableButtonStyle())
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(CT.accent.opacity(0.15)))

        Button("No Haptic") {}
            .buttonStyle(PressableButtonStyle(haptic: false))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
    .padding()
}

import SwiftUI

/// Scales the label down ~8% on press and springs back, giving tappable
/// surfaces a physical, tactile feel. Shared between the filter pills and the
/// chat input bar so the press feedback stays consistent across the app.
public struct PressableButtonStyle: ButtonStyle {
    /// Press-down scale. Default 0.92 matches the filter pills; the send button
    /// passes a slightly punchier value.
    private let pressedScale: CGFloat
    /// When true, fires a light selection haptic on press-down (default).
    /// Set to false on surfaces that provide their own haptic feedback.
    private let haptic: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(pressedScale: CGFloat = 0.92, haptic: Bool = true) {
        self.pressedScale = pressedScale
        self.haptic = haptic
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed && haptic && !reduceMotion {
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
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))

        Button("No Haptic") {}
            .buttonStyle(PressableButtonStyle(haptic: false))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
    .padding()
}

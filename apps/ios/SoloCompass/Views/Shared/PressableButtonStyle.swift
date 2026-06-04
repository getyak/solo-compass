import SwiftUI

/// Scales the label down ~8% on press and springs back, giving tappable
/// surfaces a physical, tactile feel. Shared between the filter pills and the
/// chat input bar so the press feedback stays consistent across the app.
public struct PressableButtonStyle: ButtonStyle {
    /// Press-down scale. Default 0.92 matches the filter pills; the send button
    /// passes a slightly punchier value.
    private let pressedScale: CGFloat

    public init(pressedScale: CGFloat = 0.92) {
        self.pressedScale = pressedScale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#if canImport(UIKit)
import UIKit

/// Centralized haptic feedback helper.
///
/// Guards on `UIAccessibility.isReduceMotionEnabled` as the closest public
/// proxy for the user's haptic-reduction intent (no separate "disable haptics"
/// API is exposed on iOS). Calls `prepare()` before `impactOccurred()` /
/// `notificationOccurred()` on the same instance so the Taptic Engine is
/// pre-warmed for low-latency firing.
@MainActor enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func selection() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}
#endif

#if canImport(UIKit)
import UIKit

/// Thin compatibility shim so existing call sites are unchanged but now obey
/// `hapticsEnabled`, Reduce Motion, and preview suppression via `HapticService`.
@MainActor enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        HapticService.shared.impact(style: style)
    }

    static func selection() {
        HapticService.shared.selectionChanged()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        HapticService.shared.notification(type: type)
    }
}
#endif

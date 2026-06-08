import SwiftUI

// MARK: - LongPressCardModifier

/// Attaches a long-press gesture to a card/pin so the *tap* and the *long-press*
/// can drive two different destinations:
///
///   • tap          → open the full detail sheet (the card's own `Button`/`onTap`)
///   • long-press   → float the quick preview card (`onLongPress`)
///
/// The gesture is attached only when a non-nil handler is supplied, so callers
/// that want a plain tap-only card are completely unaffected (no gesture is
/// installed, the underlying `Button` keeps its normal hit-testing).
///
/// `.onLongPressGesture` coexists with a `Button`'s tap on iOS: a quick tap fires
/// the button, a sustained press (≥ `minimumDuration`) fires the long-press and
/// suppresses the tap. A medium impact haptic confirms the long-press landed.
struct LongPressCardModifier: ViewModifier {
    let onLongPress: (() -> Void)?

    /// 0.4s matches the system default for context-menu style long-presses —
    /// short enough to feel responsive, long enough not to fire on a scroll.
    private let minimumDuration = 0.4

    func body(content: Content) -> some View {
        if let onLongPress {
            content.onLongPressGesture(minimumDuration: minimumDuration) {
                #if canImport(UIKit)
                Haptics.impact(.medium)
                #endif
                onLongPress()
            }
        } else {
            content
        }
    }
}

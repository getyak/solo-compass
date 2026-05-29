#if canImport(UIKit)
import UIKit

private extension ProcessInfo {
    var isPreview: Bool {
        environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

/// Centralised haptic feedback with a per-user opt-out via UserDefaults.
///
/// Wraps `UIImpactFeedbackGenerator` and `UINotificationFeedbackGenerator`.
/// All methods are no-ops when `hapticsEnabled` is false, when
/// `UIAccessibility.isReduceMotionEnabled` is true, or when running inside
/// an Xcode preview.
@MainActor public final class HapticService {
    public static let shared = HapticService()

    /// UserDefaults key. Defaults to `true` if the key is absent.
    static let defaultsKey = "hapticsEnabled"

    /// Whether haptics are enabled. Backed by `UserDefaults.standard` so
    /// changes made in Settings take effect immediately without an app restart.
    public var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.defaultsKey) }
    }

    private var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()

    private init() {}

    private func shouldFire() -> Bool {
        guard isEnabled else { return false }
        guard !ProcessInfo.processInfo.isPreview else { return false }
        guard !UIAccessibility.isReduceMotionEnabled else { return false }
        return true
    }

    private func generator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        if let cached = impactGenerators[style] { return cached }
        let gen = UIImpactFeedbackGenerator(style: style)
        impactGenerators[style] = gen
        return gen
    }

    /// Pre-warm the Taptic Engine for the given style. Call before the action
    /// that will fire `impact(style:)` to minimise latency.
    public func prepare(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard shouldFire() else { return }
        generator(for: style).prepare()
    }

    /// Fire an impact haptic.
    public func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard shouldFire() else { return }
        let gen = generator(for: style)
        gen.prepare()
        gen.impactOccurred()
    }

    /// Fire a selection-changed haptic.
    public func selectionChanged() {
        guard shouldFire() else { return }
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
    }

    /// Fire a notification haptic.
    public func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        guard shouldFire() else { return }
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(type)
    }
}
#endif

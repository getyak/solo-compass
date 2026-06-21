import Foundation
import TipKit

/// Solo Compass tip definitions, surfaced via SwiftUI's `.popoverTip(_:)`.
/// TipKit handles the "show once / wait for invalidation" lifecycle in the
/// system's own database so we don't reinvent dismissal tracking — but the
/// rules below decide *when* a tip becomes eligible (e.g., on the 3rd cold
/// launch, after the first filter swipe).
///
/// Adding a tip:
///   1. Define a `struct FooTip: Tip` here with `title` + `message`.
///   2. Optionally add `Rules` so the tip fires only in the right context.
///   3. In the view, attach `.popoverTip(FooTip())` to the anchor element.
///   4. SoloCompassApp's `bootstrapTips()` call already calls
///      `Tips.configure(...)` at launch — no per-tip wiring needed.

/// Cold-launch counter persisted in UserDefaults via TipKit's parameter store.
/// Bumped from SoloCompassApp on every `onAppear`.
enum TipParameters {
    @Parameter
    static var coldLaunchCount: Int = 0
}

/// Suggests the filter bar to a new user who has launched the app a few times
/// and is still on the default "All" view — they may not realize they can
/// narrow Explore results by category or by "Now".
struct FilterBarTip: Tip {
    var title: Text {
        Text("filter.tip.title", comment: "TipKit title above the filter bar")
    }

    var message: Text? {
        Text("filter.tip.message", comment: "TipKit body explaining filter chips")
    }

    var image: Image? {
        Image(systemName: "line.3.horizontal.decrease.circle")
    }

    var rules: [Rule] {
        // Show only after 2+ launches so first-launch flow stays clean.
        [
            #Rule(TipParameters.$coldLaunchCount) { $0 >= 2 }
        ]
    }
}

/// One-shot bootstrap. Idempotent — safe to call on every launch. Catches
/// `Tips.configure` errors silently so a Tip-database hiccup doesn't crash
/// the app (tips will just not appear that session).
@MainActor
public enum SoloCompassTips {
    public static func bootstrap() {
        do {
            try Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.applicationDefault)
            ])
            TipParameters.coldLaunchCount += 1
        } catch {
            // Logged but non-fatal — TipKit gracefully no-ops if init failed.
            print("⚠️ TipKit configure failed: \(error)")
        }
    }
}

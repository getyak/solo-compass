import Foundation

/// A single 60-second clock shared by every `BestNowBadge`.
///
/// Each badge previously hosted its own `TimelineView(.periodic(by: 60))`, so an
/// Explore screen with 20+ best-now badges spun up 20+ independent timelines —
/// every one waking the main actor on its own cadence and forcing a body
/// re-evaluation. US-023 collapses them into this one singleton: a lone `Timer`
/// publishes `tick` once a minute, and badges read it via
/// `@Environment(BestNowClock.self)`. SwiftUI invalidates only the views that
/// actually observe `tick`, so the visible badges still refresh every minute
/// while the allocation count stays at exactly one timer regardless of how many
/// badges are on screen.
@MainActor
@Observable
public final class BestNowClock {
    public static let shared = BestNowClock()

    /// Advances once per minute. Badges observe this to recompute their
    /// countdown label; the value itself (the current wall-clock instant) is
    /// what `BestNowBadge` feeds into `minutesLeftInBestWindow(at:)`.
    public private(set) var tick: Date

    /// Backing timer. Exactly one is allocated per clock instance — the test
    /// `BestNowBadgeClockTest` asserts on `Self.activeTimerCount` to prove that
    /// sharing one clock across N badges allocates only this single timer.
    ///
    /// `nonisolated(unsafe)` so the nonisolated `deinit` can invalidate it
    /// without an actor hop, while the main-actor `start()` can still assign it.
    /// Plain `nonisolated` won't compile here (the `timer = t` write in
    /// `start()` runs on the main actor); the same pattern is used for
    /// `SyncService.foregroundTimer` and `SubscriptionService.transactionListenerTask`.
    /// `Timer.invalidate()` is thread-safe and every other access stays on the
    /// main actor, so the unchecked annotation is sound.
    private nonisolated(unsafe) var timer: Timer?

    /// Process-wide count of live `BestNowClock` timers. Used only by tests to
    /// verify that many badges sharing one clock never spin up more than one
    /// timer. Mutated solely on the main actor.
    public private(set) static var activeTimerCount = 0

    /// - Parameter startDate: the clock's initial `tick`. Injectable so tests can
    ///   pin a deterministic instant instead of reaching for `Date()`.
    ///
    /// Passing `nil` triggers the `-scenarioHour` DEBUG launch-argument path via
    /// `AppClock.now()` so the rubric harness can pin scenario hour without the
    /// device wall clock leaking through.
    public init(startDate: Date? = nil) {
        self.tick = startDate ?? AppClock.now()
        start()
    }

    deinit {
        // `deinit` is nonisolated and may run off the main actor, so we can't
        // touch `activeTimerCount` (main-actor state) inline. Invalidate the
        // timer here — that's thread-safe — and hop to the main actor to
        // release the count slot. `activeTimerCount` exists only for the test;
        // production never reads it, so the async decrement is fine.
        timer?.invalidate()
        Task { @MainActor in
            if BestNowClock.activeTimerCount > 0 {
                BestNowClock.activeTimerCount -= 1
            }
        }
    }

    /// Install the single periodic timer. Idempotent: a second call is a no-op
    /// so re-entrancy can never leak a duplicate timer.
    private func start() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
        // Keep firing while the user scrolls the map / Explore list.
        RunLoop.main.add(t, forMode: .common)
        timer = t
        BestNowClock.activeTimerCount += 1
    }

    /// Advance `tick` to the current instant. Exposed for tests to drive the
    /// clock deterministically without waiting 60 real seconds.
    public func advance(to date: Date = Date()) {
        tick = date
    }
}

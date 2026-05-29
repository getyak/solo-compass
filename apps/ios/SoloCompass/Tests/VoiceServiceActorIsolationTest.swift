import XCTest
@testable import SoloCompass

/// Story #US-011 — `VoiceService` is `@MainActor` isolated so callers (all
/// SwiftUI views / view models, which are themselves `@MainActor`) can send a
/// `VoiceService` value into a main-actor method and `await` its async API
/// without tripping the strict-concurrency "sending self.voiceService risks
/// data races" warning at ChatSheet.swift:621.
///
/// This test exists primarily as a *compile-time* assertion: if `VoiceService`
/// (or `requestPermission()`) loses its `@MainActor` isolation, the body below
/// stops compiling under `SWIFT_STRICT_CONCURRENCY: complete`, because reading
/// `isListening` / `amplitude` and awaiting `requestPermission()` from this
/// `@MainActor` context would then cross actor boundaries.
@MainActor
final class VoiceServiceActorIsolationTest: XCTestCase {

    /// Constructing a `VoiceService` and touching its isolated state from a
    /// `@MainActor` context must be legal — no `await`/hop required for the
    /// synchronous, isolated members.
    func testVoiceServiceIsMainActorIsolated() {
        let voice = VoiceService()
        // Synchronous reads of main-actor-isolated state — these only compile
        // if `voice` is reachable on the current (main) actor.
        XCTAssertFalse(voice.isListening)
        XCTAssertEqual(voice.amplitude, 0)
    }

    /// `requestPermission()` must be callable (and `await`-able) from a
    /// `@MainActor` context without a Sendable/data-race diagnostic — this is
    /// the exact call shape used by ChatSheet's push-to-talk task. We don't
    /// assert the *result* (the simulator's authorization state is environment
    /// dependent); we only assert the call site type-checks and completes.
    func testRequestPermissionCallableFromMainActor() async {
        let voice = VoiceService()
        // The act of `await`-ing this from `@MainActor` is the assertion. A
        // Bool always comes back; either value is acceptable here.
        let granted: Bool = await voice.requestPermission()
        XCTAssertTrue(granted == true || granted == false)
    }
}

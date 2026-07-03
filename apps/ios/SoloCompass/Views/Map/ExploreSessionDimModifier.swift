import SwiftUI

/// Slice C of the Explore-Mode redesign. Applied to every experience
/// marker in `CompassMapView`. While the Explore session is active, pins
/// that are NOT part of the current session (pre-existing on the map
/// before the user tapped Explore) fade to a hushed state so the new
/// batch reads as the foreground; new pins keep full amber presence.
///
/// Idle state: no-op. The map looks exactly as it does today.
///
/// The dim treatment is intentionally lighter than the `smartPick` cold-
/// start dim: those pins fully desaturate to signal "you don't care about
/// me". Here we're just softening — the user might want to tap through to
/// a pre-existing pin during an Explore, so it must remain readable.
struct ExploreSessionDimModifier: ViewModifier {
    let isNewInSession: Bool
    let sessionActive: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let shouldDim = sessionActive && !isNewInSession
        content
            .opacity(shouldDim ? 0.42 : 1.0)
            .saturation(shouldDim ? 0.65 : 1.0)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.35),
                value: sessionActive
            )
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.35),
                value: isNewInSession
            )
    }
}

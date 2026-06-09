import SwiftUI

/// Shared "此刻最佳 / Best now" chip model for the map-browsing surfaces
/// (`PeekSummaryCard`, `NearbyExperienceRow`).
///
/// Both surfaces previously rendered a *static* golden "Best now" chip whose
/// text read identically whether the experience's best-time window had three
/// hours left or eight minutes left. The detail card (`BestNowBadge`), the
/// detail sheet, and the Saved list already surface a live countdown that flips
/// to an amber "Closing soon · Nm left" treatment once the window has ≤ 45
/// minutes remaining — but the two highest-traffic decision surfaces (the
/// resting peek pick and the Nearby list) did not, hiding the urgency at the
/// exact moment a solo traveler is choosing where to go *right now*.
///
/// This value resolves the chip's tone, glyph, label, and VoiceOver string from
/// a single live instant so the two views stay consistent with each other and
/// with the rest of the app. It is a pure, side-effect-free struct so the
/// threshold/format rules are unit-testable without a SwiftUI graph.
struct BestNowChipState {
    /// Window has ≤ `closingSoonThresholdMinutes` left → amber urgency treatment.
    let isClosingSoon: Bool
    /// Minutes remaining in the active best-time window, when known.
    let minutesLeft: Int?

    /// Threshold below which the chip flips to its amber "closing soon" form.
    /// Matches `BestNowBadge.closingSoonThresholdMinutes` and the Saved-list
    /// pill so all four surfaces agree on what "closing soon" means.
    static let closingSoonThresholdMinutes = 45

    /// Amber used for the closing-soon treatment — identical to
    /// `BestNowBadge.amber` (#F59E0B) so the urgency tone reads the same on the
    /// peek card, the Nearby row, the detail card, and the Saved list.
    static let amber = Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)

    /// Resolve the chip state for `experience` at the given instant.
    ///
    /// `minutesLeftInBestWindow(at:)` already honours weekday / season filters
    /// and windows that wrap past midnight, returning nil when no window is
    /// currently active — so a nil here means "not best now" and the caller can
    /// keep its prior visibility gating.
    static func resolve(for experience: Experience, at date: Date) -> BestNowChipState {
        let minutes = experience.minutesLeftInBestWindow(at: date)
        let closingSoon = (minutes ?? .max) <= closingSoonThresholdMinutes
        return BestNowChipState(isClosingSoon: closingSoon, minutesLeft: minutes)
    }

    /// SF Symbol for the chip: an alarm-style clock when closing soon, else the
    /// standard sparkles used by the existing "Best now" chips.
    var symbol: String {
        isClosingSoon ? "clock.badge.exclamationmark" : "sparkles"
    }

    /// Foreground tint: amber when closing soon, else the warm sun-gold-deep
    /// used by the existing chips.
    var foreground: Color {
        isClosingSoon ? Self.amber : CT.sunGoldDeep
    }

    /// Capsule fill: a soft amber wash when closing soon, else the existing
    /// sun-gold-soft.
    var background: Color {
        isClosingSoon ? Self.amber.opacity(0.16) : CT.sunGoldSoft
    }

    /// Visible chip label. When closing soon and a minute count is known, shows
    /// the compact countdown ("Closing · Nm"); otherwise the plain "Best now".
    var label: String {
        if isClosingSoon, let minutes = minutesLeft {
            return String(
                format: NSLocalizedString(
                    "nearby.chip.closingSoon",
                    comment: "Compact closing-soon chip on map cards, e.g. 'Closing · 12m'"
                ),
                minutes
            )
        }
        return NSLocalizedString("nearby.chip.bestNow", comment: "此刻最佳 chip")
    }

    /// VoiceOver phrase appended to the card's accessibility label.
    var accessibilityLabel: String {
        if isClosingSoon, let minutes = minutesLeft {
            return String(
                format: NSLocalizedString(
                    "nearby.chip.closingSoon.a11y",
                    comment: "VoiceOver: best now but closing soon, with minutes left"
                ),
                minutes
            )
        }
        return NSLocalizedString("nearby.chip.bestNow", comment: "此刻最佳 chip")
    }
}

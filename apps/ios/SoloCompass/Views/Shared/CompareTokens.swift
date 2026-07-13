import SwiftUI
import UIKit

// Design tokens lifted verbatim from CompareCanvas.html (claude.ai/design handoff).
// Use these when a view is a direct port of a Route / Companion design surface.
// For everything else, prefer SwiftUI system semantic colors so dark mode keeps working.
public enum CT {

    // MARK: - Color palette (mirrors --bg-warm / --fg-* / --accent-* / surface / border in styles.css)
    public static let bgWarm        = rgb(0xFA, 0xF8, 0xF6)
    public static let surfaceWhite  = rgb(0xFF, 0xFF, 0xFF)
    public static let surfaceSunken = rgb(0xF3, 0xEE, 0xE6)
    public static let fgPrimary     = rgb(0x1F, 0x1A, 0x14)
    public static let fgMuted       = rgb(0x6D, 0x63, 0x58)
    public static let fgSubtle      = rgb(0xA3, 0x9A, 0x8C)
    public static let borderSubtle  = rgb(0xED, 0xE8, 0xDF)
    public static let borderDefault = rgb(0xD6, 0xCE, 0xC0)
    public static let accent        = rgb(0x5D, 0x30, 0x00)
    public static let accentHover   = rgb(0x4A, 0x26, 0x00)
    public static let accentSoft    = rgb(0xFB, 0xF1, 0xE4)
    public static let accentBorder  = rgb(0xE8, 0xDC, 0xCA)

    // Sun-gold — "此刻" / now semantics (sunset tones; --sun-gold* in styles.css)
    public static let sunGold       = rgb(0xC9, 0xA6, 0x77)
    public static let sunGoldDeep   = rgb(0xA0, 0x7F, 0x4B)
    public static let sunGoldSoft   = rgb(0xF5, 0xE9, 0xD2)

    // Chat surface tokens. All light-fixed values — pair with a colorScheme
    // check at the call site so the warm tints don't fight dark mode.
    public static let chatInputBg         = rgb(0xF5, 0xF0, 0xEB) // warm input-field fill
    public static let bannerError         = rgb(0xC0, 0x3B, 0x1E) // #C03B1E — banner error tone
    public static let chatAIBubbleBgDark  = rgb(0x28, 0x24, 0x1E) // dark-mode AI bubble fill

    // Dark-mode warm neutrals — keep the amber identity alive on a near-black
    // sheet instead of falling back to cold systemGray. Sheet → card → sunken
    // form a low-contrast warm-charcoal ladder; warm hairline borders separate
    // them without the harsh blue-gray of `.separator`.
    public static let warmSheetDark   = rgb(0x17, 0x14, 0x10) // sheet base
    public static let warmCardDark    = rgb(0x23, 0x1F, 0x19) // raised card fill
    public static let warmSunkenDark  = rgb(0x2C, 0x27, 0x20) // icon tile / sunken
    public static let warmBorderDark  = rgb(0x3A, 0x33, 0x29) // hairline on dark
    public static let fgPrimaryDark   = rgb(0xF4, 0xEF, 0xE7) // warm off-white text
    public static let fgMutedDark     = rgb(0xB0, 0xA6, 0x97) // warm secondary text

    // Verified green (路线已验证 / closed companion) — #1F7B4D text, #2FA46A dot.
    public static let verifiedGreen    = rgb(0x1F, 0x7B, 0x4D)
    public static let verifiedGreenDot = rgb(0x2F, 0xA4, 0x6A)

    // Status tones — open / forming / closed / completed.
    // Sourced verbatim from styles.css .status-pill.tone-* (route detail recruiting):
    //   open=accent #5D3000 · forming=#B57420 · closed(已成团/green) #1F7B4D · completed=fg-muted #6D6358
    public static let toneOpen      = rgb(0x5D, 0x30, 0x00)
    public static let toneForming   = rgb(0xB5, 0x74, 0x20)
    public static let toneClosed    = rgb(0x1F, 0x7B, 0x4D)
    public static let toneCompleted = rgb(0x6D, 0x63, 0x58)

    // Warning / success soft tints — honest-caveat cards + verified states.
    // From styles.css --warning-soft/--warning + --success-soft/--success used by
    // .sc-caveat, .sc-trust-chip, .sc-note-status, .sc-hours-line .open.
    public static let warningSoft   = rgb(0xFB, 0xF2, 0xE3) // amber caveat-card fill
    public static let warningText   = rgb(0xB5, 0x74, 0x20) // #B57420 amber label (3.83:1 — large/bold only)
    /// Darkened amber label — #9E5F00, 4.62:1 on warningSoft / 5.13:1 on white.
    /// Use for warning/caveat text under ~18.66px non-bold so it passes WCAG AA
    /// (audit color-05). Keep `warningText` only where the label is genuinely
    /// large (≥18.66px) or true-bold ≥14pt.
    public static let warningTextStrong = rgb(0x9E, 0x5F, 0x00)
    public static let successSoft   = Color(.sRGB, red: 0x2F / 255, green: 0xA4 / 255, blue: 0x6A / 255, opacity: 0.12)
    public static let successText   = rgb(0x1F, 0x7B, 0x4D) // = verifiedGreen

    // MARK: - Warm-amber v2 scene tokens (Phase 2 X.1 #X10)
    //
    // Scene-specific warm-amber tints for Phase 2 signature moments. Each is
    // a tuned point on the same sunGold/sunset ramp; use them where the base
    // sunGold triple isn't specific enough to convey the emotional register
    // (capsule discovery = glow, daily omen = the day's specific hue, blindbox
    // reveal = deeper amber). Keep semantics disciplined: don't paint routine
    // affordances with these — that's what the base sunGold/accent ladder is
    // for. These earn their weight only on ritual surfaces.

    /// TimeCapsule "buried & discovered" glow — a lighter, more ethereal
    /// amber than sunGold, used for the capsule accept animation surface and
    /// the Live Activity's capsule kind.
    public static let capsuleGlow    = rgb(0xF7, 0xDE, 0xB0)

    /// Daily-omen card tint — a deeper, more mineral gold than sunGold, used
    /// for the OmenCard face and its lock-screen Live Activity accent. Sits
    /// between sunGold (0xC9A677) and sunGoldDeep (0xA07F4B).
    public static let omenGold       = rgb(0xB8, 0x92, 0x5C)

    /// Blindbox reveal amber — the richest tone on the ramp, reserved for the
    /// blindbox recap card and the launch button gradient. Deeper than accent
    /// (0x5D3000) to avoid competing with the primary accent CTA.
    public static let blindboxAmber  = rgb(0x8A, 0x4A, 0x14)

    // Saved/favourite warm red — used on the Saved filter pill and heart icons.
    public static let savedRed      = rgb(0xE0, 0x3A, 0x3A)
    public static let savedRedSoft  = Color(.sRGB, red: 0xE0 / 255, green: 0x3A / 255, blue: 0x3A / 255, opacity: 0.12)

    // Heatmap scale — Solo-Score dimension bars (styles.css .sc-solo-card .dim .fill).
    // hi=deep amber accent · mid=sun-gold · lo=pale amber · empty=track. An amber
    // ramp replaces red/green so the breakdown stays in the warm system.
    public static let heatmapHi     = accent
    public static let heatmapMid    = sunGold
    public static let heatmapLow    = rgb(0xE6, 0xD9, 0xC3)
    public static let heatmapEmpty  = rgb(0xF0, 0xEB, 0xE3)

    // MARK: - City OS v2 · sanctioned exceptions (PRD solo-city-os-v2 §2)
    //
    // The first color axiom is "don't invent new color semantics". These three
    // are the ONLY exception, and they come from the claude.ai/design handoff
    // bundle — not from an ad-hoc choice here:
    //   • Limited-time events read as a distinct register from the warm map
    //     (they expire — the timer ring on the回流 marker + the "仅本周" chip).
    //     A burnt-orange, warmer and more urgent than sunGold, carries that
    //     without leaving the amber family.
    //   • Plan mode is a *different city context*, not a filter; its wash and
    //     mode tag use a cool blue so the traveler feels the register flip from
    //     Live (warm/amber) to Plan (cool/considered).
    // Keep these disciplined: eventLimited* only on limited-time event surfaces;
    // modePlanBlue only on Plan-mode chrome.

    /// Limited-time event accent — #B5541A burnt orange, for the 回流 map
    /// marker's breathing ring stroke and the "仅本周" limited chip text.
    public static let eventLimited     = rgb(0xB5, 0x54, 0x1A)
    /// Soft fill behind limited-event chips / notice bands — #FFEEDD.
    public static let eventLimitedSoft = rgb(0xFF, 0xEE, 0xDD)
    /// Plan-mode blue — #2F7DD1, for the Plan wash tint and mode tag.
    public static let modePlanBlue     = rgb(0x2F, 0x7D, 0xD1)

    // MARK: - Scrims & overlays (audit H10)
    //
    // Use these tokens when the dim / wash / shadow is applied *over a
    // warm-amber surface* and should evolve with the palette — for example
    // peek-sheet handle bars, modal scrims, glassmorphism capsules over a
    // map background, or shadow tints on cards.
    //
    // What NOT to convert: `Color.black/.white.opacity()` is the *right*
    // primitive when the surface is intentionally a deep dark-bubble
    // (chat AI bubble, share-card hero gradient, voice-record mic, dark
    // marker) — those want literal black/white regardless of palette and
    // forcing them through this namespace would invert the contrast when
    // someone tweaks the warm scrim later. The audit (H10) flagged ~17
    // files; a careful pass shows ~13 are this decorative-on-dark case
    // (ShareCard*, AttachmentBubble, VoiceButton mic, MarkerIconView
    // fallback, ChatSheet dark-bubble overlay, etc.) and should stay as
    // literal `Color.black/.white.opacity()`. The remaining four are
    // FilterBar badge highlights and the SkeletonView shimmer — small
    // enough that introducing wash tokens for them costs more than the
    // duplication. Conclusion: keep these tokens available for the
    // *new* surfaces that need to be palette-aware; do not bulk-rewrite
    // existing call sites.
    /// Light dim used over warm map backgrounds (e.g. peek sheet handle bar).
    public static let scrimSoft     = Color.black.opacity(0.08)
    /// Card / sheet shadow tint.
    public static let scrimShadow   = Color.black.opacity(0.12)
    /// Heavier overlay used behind modal alerts / takeover sheets.
    public static let scrimModal    = Color.black.opacity(0.32)
    /// White wash used over hero photos to lift legibility of overlay text.
    public static let washLight     = Color.white.opacity(0.85)
    /// Glassmorphism capsule fill — warm white with subtle translucency.
    public static let washCapsule   = Color.white.opacity(0.72)

    // MARK: - Adaptive color tokens (audit color-02)
    //
    // ~75 call sites hand-wrote the SAME `colorScheme == .dark ? CT.xDark : CT.x`
    // ternary inline. These five tokens fold that duplication into one place using
    // a dynamic UIColor provider, so a call site can drop the ternary (and often
    // its `@Environment(\.colorScheme)`) and just use the adaptive token.
    //
    // DISCIPLINE (do not skip — see audit color-02 adjusted_fix):
    //  • These are ONLY for surfaces that were ALREADY colorScheme-aware. The
    //    46 fixed white cards (`CT.surfaceWhite` with near-black `CT.fgPrimary`,
    //    no colorScheme branch) are intentional light-fixed cards — DO NOT swap
    //    them to these adaptive tokens, or a fixed white card would go dark.
    //  • `cardAdaptive` (bg) and `textPrimaryAdaptive` (text) must be adopted as a
    //    PAIR on the same view so contrast stays self-consistent.
    //  • Semantic (non-mechanical) dark mappings — e.g. `warmSunkenDark : accentSoft`,
    //    `fgPrimaryDark : sunGoldDeep` — are NOT covered here; keep those explicit.
    //
    // `Color(UIColor { ... })` resolves per-trait at render time (iOS 13+), so it
    // adapts to light/dark for backgrounds, fills, and foreground styles alike.

    /// Raised card fill — surfaceWhite (light) / warmCardDark (dark).
    public static let cardAdaptive        = adaptive(light: 0xFF, 0xFF, 0xFF, dark: 0x23, 0x1F, 0x19)
    /// Sheet / sunken base — surfaceSunken (light) / warmSheetDark (dark).
    public static let sheetAdaptive       = adaptive(light: 0xF3, 0xEE, 0xE6, dark: 0x17, 0x14, 0x10)
    /// Primary text — fgPrimary (light) / fgPrimaryDark (dark).
    public static let textPrimaryAdaptive = adaptive(light: 0x1F, 0x1A, 0x14, dark: 0xF4, 0xEF, 0xE7)
    /// Secondary text — fgMuted (light) / fgMutedDark (dark).
    public static let textMutedAdaptive   = adaptive(light: 0x6D, 0x63, 0x58, dark: 0xB0, 0xA6, 0x97)
    /// Hairline border — borderSubtle (light) / warmBorderDark (dark).
    public static let borderAdaptive      = adaptive(light: 0xED, 0xE8, 0xDF, dark: 0x3A, 0x33, 0x29)
    /// Full-page warm ground — bgWarm (light) / warmSheetDark (dark). For the
    /// page-level `.background(CT.bgWarm)` on full-screen surfaces that must go
    /// dark instead of staying a light-locked white page (audit color-01).
    public static let pageAdaptive        = adaptive(light: 0xFA, 0xF8, 0xF6, dark: 0x17, 0x14, 0x10)

    /// Builds a light/dark-adaptive `Color` from two RGB triples. Mirrors the
    /// `rgb()` factory below but resolves per `userInterfaceStyle` at render time.
    private static func adaptive(
        light lr: Int, _ lg: Int, _ lb: Int,
        dark dr: Int, _ dg: Int, _ db: Int
    ) -> Color {
        Color(UIColor { traits in
            let (r, g, b) = traits.userInterfaceStyle == .dark ? (dr, dg, db) : (lr, lg, lb)
            return UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        })
    }

    // MARK: - Typography (Space Grotesk / Inter / JetBrains Mono → system fallback)
    // `display` keeps the existing default-design fallback so chat/route surfaces
    // that already shipped stay byte-identical. `displayRounded` is the new
    // detail-page title face: SF Rounded is the closest system match to Space
    // Grotesk's geometric sans.
    public static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    public static func displayRounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    public static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    public static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}

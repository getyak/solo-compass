import SwiftUI

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

    // MARK: - Typography (Space Grotesk / Inter / JetBrains Mono → system fallback)
    public static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
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

import SwiftUI

/// Hacker-aesthetic dark theme, calibrated against the GitHub-dark ("Primer")
/// palette so every foreground/background pairing clears WCAG AA (4.5:1).
///
/// Design intent (audited US-051):
/// - `background` #0D1117  — near-black "obsidian" canvas (GitHub dark default).
/// - `surface`    #161B22  — one step lighter for cards/sheets above the canvas.
/// - `accent`     #39FF14  — neon "terminal green"; the signature hacker accent.
/// - `secondary`  #58A6FF  — Primer link-blue for secondary emphasis.
/// - `primaryText`#E6EDF3  — Primer `fg.default`, high-contrast body text.
/// - `secondaryText` #8B949E — Primer `fg.muted`; nudged up one notch from the
///   prior #89939E so muted text clears 4.5:1 on `surface`, not just `background`.
///
/// All hex values are surfaced as `*RGB` tuples below so `ObsidianThemeContrastTest`
/// can verify the WCAG ratios stay above threshold if any value is ever retuned.
public struct ObsidianTheme: Theme {
    public let name = "Obsidian"

    // MARK: - Calibrated palette (8-bit sRGB), single source of truth.
    static let backgroundRGB    = (r: 0x0D, g: 0x11, b: 0x17) // #0D1117
    static let surfaceRGB       = (r: 0x16, g: 0x1B, b: 0x22) // #161B22
    static let accentRGB        = (r: 0x39, g: 0xFF, b: 0x14) // #39FF14
    static let secondaryRGB     = (r: 0x58, g: 0xA6, b: 0xFF) // #58A6FF
    static let primaryTextRGB   = (r: 0xE6, g: 0xED, b: 0xF3) // #E6EDF3
    static let secondaryTextRGB = (r: 0x8B, g: 0x94, b: 0x9E) // #8B949E

    public var background: Color { Self.color(Self.backgroundRGB) }
    public var surface: Color { Self.color(Self.surfaceRGB) }
    public var accent: Color { Self.color(Self.accentRGB) }
    public var secondary: Color { Self.color(Self.secondaryRGB) }
    public var primaryText: Color { Self.color(Self.primaryTextRGB) }
    public var secondaryText: Color { Self.color(Self.secondaryTextRGB) }

    static func color(_ rgb: (r: Int, g: Int, b: Int)) -> Color {
        Color(red: Double(rgb.r) / 255.0, green: Double(rgb.g) / 255.0, blue: Double(rgb.b) / 255.0)
    }

    public init() {}
}

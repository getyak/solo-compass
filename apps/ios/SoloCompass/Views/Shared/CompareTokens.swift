import SwiftUI

// Design tokens lifted verbatim from CompareCanvas.html (claude.ai/design handoff).
// Use these when a view is a direct port of a Route / Companion design surface.
// For everything else, prefer SwiftUI system semantic colors so dark mode keeps working.
public enum CT {

    // MARK: - Color palette (mirrors --bg-warm / --fg-* / --accent-* in styles.css)
    public static let bgWarm        = rgb(0xFA, 0xF8, 0xF6)
    public static let fgPrimary     = rgb(0x1F, 0x1A, 0x14)
    public static let fgMuted       = rgb(0x6D, 0x63, 0x58)
    public static let fgSubtle      = rgb(0xA3, 0x9A, 0x8C)
    public static let accent        = rgb(0x5D, 0x30, 0x00)
    public static let accentHover   = rgb(0x4A, 0x26, 0x00)
    public static let accentSoft    = rgb(0xFB, 0xF1, 0xE4)
    public static let accentBorder  = rgb(0xE8, 0xDC, 0xCA)

    // Status tones — open / forming / closed / completed (sourced from chat2.md)
    public static let toneOpen      = rgb(0x1F, 0x7B, 0x4D)
    public static let toneForming   = rgb(0x8C, 0x6A, 0x1A)
    public static let toneClosed    = rgb(0x5D, 0x30, 0x00)
    public static let toneCompleted = rgb(0x1F, 0x7B, 0x4D)

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

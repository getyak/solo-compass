import SwiftUI

/// Warm-amber palette for the Live Activity / Dynamic Island surfaces.
///
/// The main app owns the full `CT` token set (`Views/Shared/CompareTokens.swift`),
/// but `CT` lives in the app target and leans on SwiftUI semantic colors. Rather
/// than drag the whole `Views/Shared` tree into the extension, this mirrors only
/// the handful of tokens the island needs, sourced verbatim from the same hex
/// values in `island_notif.css` (DayPage warm-amber system):
///
///   --accent #5D3000 · --sun-gold #C9A677 · --sun-gold-soft #F5E9D2 · --rec #C0492F
///   plus the cream tones used for text on the black island glass.
///
/// Keep this in lockstep with `CT` if those hex values ever change.
enum IP {
    // Brand / now-semantic ambers (= CT.accent / CT.sunGold* / styles.css --sun-gold*)
    static let accent       = hex(0x5D3000)
    static let sunGold      = hex(0xC9A677)
    static let sunGoldDeep  = hex(0xA07F4B)
    static let sunGoldSoft  = hex(0xF5E9D2)
    static let rec          = hex(0xC0492F)   // recording red

    // Cream tones for text/lines on the black island (styles.css --cream*)
    static let cream        = hex(0xF5EFE6)
    static func cream(_ a: Double) -> Color { hex(0xF5EFE6).opacity(a) }

    // Avatar fallback colors used by the countdown member stack
    // (mirror styles.css inline avatar colors: #E89530 / #2F7DD1 + accent).
    static let avatarAmber = hex(0xE89530)
    static let avatarBlue  = hex(0x2F7DD1)

    // Amber-tinted icon-tile fills / pill backgrounds (styles.css .exp-ic / .exp-pill).
    static let goldTile    = hex(0xC9A677).opacity(0.18)
    static let goldPill    = hex(0xC9A677).opacity(0.16)
    static let goldBorder  = hex(0xC9A677).opacity(0.24)
    static let recTile     = hex(0xC0492F).opacity(0.20)

    static func hex(_ v: Int) -> Color {
        Color(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Font {
    /// Monospaced digits — the island spec puts every number in JetBrains Mono;
    /// SF Mono is the system stand-in. Used for countdowns, ETAs, durations.
    static func islandMono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// Rounded geometric sans for place names / titles (≈ Space Grotesk).
    static func islandDisplay(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

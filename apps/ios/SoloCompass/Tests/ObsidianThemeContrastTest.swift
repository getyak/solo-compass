import XCTest
@testable import SoloCompass

/// US-051: the calibrated ObsidianTheme dark palette must be legible. Every text
/// color must clear WCAG AA (4.5:1) against BOTH the canvas (`background`) and the
/// elevated `surface` it can sit on, and the chromatic accents (`accent`,
/// `secondary`) must clear AA against both as well so they read as foreground.
///
/// Mirrors the WCAG relative-luminance math used by `FilterChipContrastTest`.
@MainActor
final class ObsidianThemeContrastTest: XCTestCase {

    /// WCAG 2.x relative luminance for an 8-bit sRGB channel triple.
    /// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
    private func relativeLuminance(_ rgb: (r: Int, g: Int, b: Int)) -> Double {
        func linearize(_ channel: Int) -> Double {
            let c = Double(channel) / 255.0
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(rgb.r)
             + 0.7152 * linearize(rgb.g)
             + 0.0722 * linearize(rgb.b)
    }

    /// WCAG contrast ratio: (L_lighter + 0.05) / (L_darker + 0.05).
    private func contrastRatio(
        _ a: (r: Int, g: Int, b: Int),
        _ b: (r: Int, g: Int, b: Int)
    ) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func assertAA(
        _ fg: (r: Int, g: Int, b: Int),
        on bg: (r: Int, g: Int, b: Int),
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ratio = contrastRatio(fg, bg)
        XCTAssertGreaterThanOrEqual(
            ratio, 4.5,
            "ObsidianTheme \(label) must meet WCAG AA (4.5:1); got \(String(format: "%.2f", ratio))",
            file: file, line: line
        )
    }

    func testTextColorsMeetWCAGAAOnBackground() {
        assertAA(ObsidianTheme.primaryTextRGB,   on: ObsidianTheme.backgroundRGB, "primaryText on background")
        assertAA(ObsidianTheme.secondaryTextRGB, on: ObsidianTheme.backgroundRGB, "secondaryText on background")
    }

    func testTextColorsMeetWCAGAAOnSurface() {
        assertAA(ObsidianTheme.primaryTextRGB,   on: ObsidianTheme.surfaceRGB, "primaryText on surface")
        assertAA(ObsidianTheme.secondaryTextRGB, on: ObsidianTheme.surfaceRGB, "secondaryText on surface")
    }

    func testAccentsMeetWCAGAA() {
        assertAA(ObsidianTheme.accentRGB,    on: ObsidianTheme.backgroundRGB, "accent on background")
        assertAA(ObsidianTheme.accentRGB,    on: ObsidianTheme.surfaceRGB,    "accent on surface")
        assertAA(ObsidianTheme.secondaryRGB, on: ObsidianTheme.backgroundRGB, "secondary on background")
        assertAA(ObsidianTheme.secondaryRGB, on: ObsidianTheme.surfaceRGB,    "secondary on surface")
    }

    /// The calibrated palette must back the live `Color` tokens: the RGB tuples
    /// the test asserts on are the same values the theme renders.
    func testPaletteTuplesBackLiveColors() {
        let theme = ObsidianTheme()
        XCTAssertEqual(theme.background.description,
                       ObsidianTheme.color(ObsidianTheme.backgroundRGB).description)
        XCTAssertEqual(theme.accent.description,
                       ObsidianTheme.color(ObsidianTheme.accentRGB).description)
    }
}

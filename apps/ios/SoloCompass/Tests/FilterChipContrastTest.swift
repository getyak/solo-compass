import XCTest
@testable import SoloCompass

/// US-028: the selected filter chip must meet WCAG AA (4.5:1) text contrast for
/// low-vision users. The old #D4A843 gold fill under white text cleared only
/// ~1.9:1; this test computes the WCAG relative luminance of the current
/// selected-state foreground/background and asserts the ratio stays ≥ 4.5.
@MainActor
final class FilterChipContrastTest: XCTestCase {

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

    /// WCAG contrast ratio between two colors: (L_lighter + 0.05) / (L_darker + 0.05).
    private func contrastRatio(
        _ a: (r: Int, g: Int, b: Int),
        _ b: (r: Int, g: Int, b: Int)
    ) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        let lighter = max(la, lb)
        let darker = min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func testSelectedChipContrastMeetsWCAGAA() {
        let ratio = contrastRatio(
            FilterBarView.selectedForegroundRGB,
            FilterBarView.selectedFillRGB
        )
        XCTAssertGreaterThanOrEqual(
            ratio, 4.5,
            "Selected filter chip foreground/background contrast must meet WCAG AA (4.5:1); got \(ratio)"
        )
    }

    /// The chosen pairing (white on CT.accent #5D3000) is specified to clear the
    /// stricter AAA / large-text threshold of 7:1 as well.
    func testSelectedChipContrastMeetsAAA() {
        let ratio = contrastRatio(
            FilterBarView.selectedForegroundRGB,
            FilterBarView.selectedFillRGB
        )
        XCTAssertGreaterThanOrEqual(ratio, 7.0, "Selected chip contrast should clear 7:1; got \(ratio)")
    }

    /// Guard rail: confirm the regressed #D4A843-on-white pairing the story
    /// replaced would in fact FAIL the AA bar, so the test is meaningfully tied
    /// to the fix and not trivially passing.
    func testLegacyGoldPairingWouldHaveFailed() {
        let legacyGold = (r: 0xD4, g: 0xA8, b: 0x43)
        let white = (r: 0xFF, g: 0xFF, b: 0xFF)
        let ratio = contrastRatio(white, legacyGold)
        XCTAssertLessThan(ratio, 4.5, "Sanity check: the old gold-on-white selected state should fail AA; got \(ratio)")
    }
}

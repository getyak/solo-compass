import XCTest
@testable import SoloCompass

/// Visual-polish guard for the chat surface: the new bubble + input + banner
/// color pairings must stay legible. Mirrors the WCAG relative-luminance math
/// in `FilterChipContrastTest` so the chat redesign can't silently regress the
/// way the old gold filter chip did.
@MainActor
final class ChatBubbleContrastTest: XCTestCase {

    // MARK: - WCAG helpers (same algorithm as FilterChipContrastTest)

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

    // MARK: - Token RGB (mirrors CompareTokens.CT light-mode values)

    private let white         = (r: 0xFF, g: 0xFF, b: 0xFF)
    private let accent        = (r: 0x5D, g: 0x30, b: 0x00) // CT.accent — user bubble fill
    private let fgPrimary     = (r: 0x1F, g: 0x1A, b: 0x14) // CT.fgPrimary — body text
    private let chatInputBg   = (r: 0xF5, g: 0xF0, b: 0xEB) // CT.chatInputBg — input fill
    private let bannerError   = (r: 0xC0, g: 0x3B, b: 0x1E) // CT.bannerError — banner rail/icon
    private let surfaceSunken = (r: 0xF3, g: 0xEE, b: 0xE6) // CT.surfaceSunken — banner bg

    // MARK: - Tests

    /// White body text on the user bubble (CT.accent) must clear the stricter
    /// AAA bar (7:1), matching the filter-chip selected-state spec.
    func testUserBubbleTextMeetsWCAGAAA() {
        let ratio = contrastRatio(white, accent)
        XCTAssertGreaterThanOrEqual(
            ratio, 7.0,
            "White text on CT.accent user bubble must clear AAA (7:1); got \(ratio)"
        )
    }

    /// Primary body text on the warm chat input fill must meet WCAG AA (4.5:1).
    func testInputTextMeetsWCAGAA() {
        let ratio = contrastRatio(fgPrimary, chatInputBg)
        XCTAssertGreaterThanOrEqual(
            ratio, 4.5,
            "CT.fgPrimary on CT.chatInputBg must meet AA (4.5:1); got \(ratio)"
        )
    }

    /// The error banner's rail/icon tone on the sunken surface must clear the
    /// 3:1 non-text / large-text bar so the accent reads as a deliberate cue.
    func testBannerErrorMeetsNonTextContrast() {
        let ratio = contrastRatio(bannerError, surfaceSunken)
        XCTAssertGreaterThanOrEqual(
            ratio, 3.0,
            "CT.bannerError on CT.surfaceSunken must meet 3:1 non-text contrast; got \(ratio)"
        )
    }
}

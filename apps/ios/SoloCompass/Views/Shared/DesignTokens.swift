import SwiftUI

// MARK: - Design system primitives (Phase 1 — aesthetic-audit remediation)
//
// These three enums + the glassSurface() modifier are the geometry & material
// layer of the design system. CT (CompareTokens.swift) owns *color*; this file
// owns *space, radius, elevation, and material*. Together they replace the
// scattered magic numbers the audit flagged (15 cornerRadius values, 15 padding
// values, 76 hand-written shadows, 54 ad-hoc materials).
//
// Adoption is incremental and non-breaking: introducing these tokens changes
// nothing visually until a call site opts in. Each value below maps a real
// cluster of existing magic numbers onto the nearest step of a disciplined
// scale, so a call site swapping `14` → `Radius.md` shifts by ≤2pt — imperceptible
// individually, but the whole app snaps onto one rhythm.

// MARK: Space — 4pt spacing ladder
//
// Collapses the 15 observed padding values (2,3,4,6,8,10,12,14,16,18,20,24,28,32,40)
// onto a strict 4pt grid. Use for padding, stack spacing, and gaps.
public enum Space {
    /// 2pt — hairline nudge (badge insets, tight icon gaps).
    public static let xxs: CGFloat = 2
    /// 4pt — smallest real gap.
    public static let xs: CGFloat = 4
    /// 8pt — dense element spacing (icon ↔ label).
    public static let sm: CGFloat = 8
    /// 12pt — default intra-card spacing.
    public static let md: CGFloat = 12
    /// 16pt — standard card / row padding (the app's most common value).
    public static let lg: CGFloat = 16
    /// 20pt — generous section padding.
    public static let xl: CGFloat = 20
    /// 24pt — inter-section breathing room.
    public static let xxl: CGFloat = 24
    /// 32pt — large layout gutters, sheet top padding.
    public static let xxxl: CGFloat = 32
}

// MARK: Radius — 4-step corner ladder
//
// Collapses the 15 observed cornerRadius values onto four rungs. Mapping guide
// for the batch pass (§ audit spacing lens): 3/4/6/7/8/9 → sm · 10/12/14 → md ·
// 16/18/20 → lg · 22/24/25 → xl · full pills → pill.
public enum Radius {
    /// 8pt — chips, badges, small controls.
    public static let sm: CGFloat = 8
    /// 12pt — inner tiles, compact cards.
    public static let md: CGFloat = 12
    /// 16pt — standard cards, sheets content (the app's dominant large radius).
    public static let lg: CGFloat = 16
    /// 20pt — hero surfaces, prominent sheets (folds 20/22/24/25 per audit radius-01).
    public static let xl: CGFloat = 20
    /// Fully-rounded capsule/pill.
    public static let pill: CGFloat = 999

    /// A `RoundedRectangle` at `r`, always `.continuous` (squircle). Use this as
    /// the single source of card/sheet shapes so the app can't drift back into
    /// the 146-continuous-vs-133-bare split the audit flagged (radius-04). The
    /// continuous corner is Apple's platform standard and matches Liquid Glass.
    public static func shape(_ r: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: r, style: .continuous)
    }
}

public extension View {
    /// Clips to a continuous rounded rectangle at `r`. Replaces bare
    /// `.cornerRadius(r)` / `RoundedRectangle(cornerRadius: r)` (no `.continuous`)
    /// so every card corner in the app is a squircle (audit radius-04).
    func ctCornerRadius(_ r: CGFloat) -> some View {
        clipShape(Radius.shape(r))
    }
}

// MARK: Elevation — three shadow presets
//
// Collapses the 76 hand-written .shadow() calls onto three semantic tiers.
// Values follow the HIG/apple-design "bigger surfaces read as thicker" rule:
// larger surfaces get a wider, softer, more-offset shadow. The tint is warm-
// neutral (near-black with the tiniest amber bias) rather than pure black, so
// shadows sit inside the palette instead of reading as a cold gray halo.
public enum Elevation {
    public struct Preset {
        public let color: Color
        public let radius: CGFloat
        public let x: CGFloat
        public let y: CGFloat
    }

    /// Warm shadow tint — #1F1A14 (CT.fgPrimary) at low opacity. Keeps shadows
    /// in the amber system rather than a cold pure-black.
    private static let warmScrim = Color(.sRGB, red: 0x1F / 255, green: 0x1A / 255, blue: 0x14 / 255, opacity: 1)

    /// Card — a resting surface just above the background.
    public static let card = Preset(color: warmScrim.opacity(0.08), radius: 8, x: 0, y: 2)
    /// Sheet — a floating panel / bottom sheet lifted off content.
    public static let sheet = Preset(color: warmScrim.opacity(0.12), radius: 16, x: 0, y: 6)
    /// Modal — a takeover surface that must read as clearly in front.
    public static let modal = Preset(color: warmScrim.opacity(0.18), radius: 28, x: 0, y: 12)
}

public extension View {
    /// Applies a named elevation preset. Replaces bespoke `.shadow(color:radius:x:y:)`
    /// calls so the app has exactly three shadow depths.
    func elevation(_ preset: Elevation.Preset) -> some View {
        shadow(color: preset.color, radius: preset.radius, x: preset.x, y: preset.y)
    }
}

// MARK: - glassSurface — Liquid Glass with an iOS 17 fallback
//
// The product targets iOS 17.0, so `.glassEffect` (iOS 26) cannot be used
// unconditionally. This modifier gates it: on iOS 26+ the surface gets true
// Liquid Glass; on iOS 17–25 it falls back to the unified material tier the
// audit prescribes ("bigger surface = thicker material"). Call sites pick the
// tier by *surface size*, not by guesswork.
//
// Discipline (per axiom-design): never stack glass on glass; tint only primary
// actions; let the system own legibility. Reduce-transparency downgrades the
// fallback material automatically via SwiftUI.

public enum GlassTier {
    /// Structural chrome — sheets, nav bars, large floating panels. Thicker.
    case structural
    /// Small controls — chips, the locate button, compact capsules. Lighter.
    case control

    fileprivate var fallbackMaterial: Material {
        switch self {
        case .structural: return .regularMaterial
        case .control:    return .thinMaterial
        }
    }
}

public extension View {
    /// Applies a Liquid Glass surface (iOS 26+) or the unified material fallback
    /// (iOS 17–25), clipped to `shape`. Use instead of ad-hoc `.background(.xMaterial, in:)`.
    ///
    /// - Parameters:
    ///   - tier: structural (thick) vs control (thin) — chosen by surface size.
    ///   - shape: the clip/glass shape (default: Capsule).
    @ViewBuilder
    func glassSurface(
        _ tier: GlassTier = .structural,
        in shape: some Shape = Capsule()
    ) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(tier.fallbackMaterial, in: shape)
        }
    }
}

// MARK: - Dynamic Type — size-preserving scaled fonts (audit font-01)
//
// The CT.display/body/mono(size:) factories return a *fixed* .system(size:) that
// never responds to the user's text-size setting — the root cause the audit
// flagged for ~144 body-text call sites. These modifiers wrap the SAME point
// size in @ScaledMetric so the exact size (13, 13.5, 14 …) is preserved at the
// default text size and scales proportionally with Dynamic Type — the Apple-
// sanctioned way to keep a bespoke size AND honor accessibility, without the
// lossy bucketing that mapping to a TextStyle would cause.
//
// Migration: `.font(CT.body(13, .medium))` → `.ctBody(13, .medium)`. Purely
// decorative display glyphs (large emoji/SF Symbols) and ImageRenderer export
// canvases (ShareCard*) should KEEP the fixed CT.body/display factories — a
// share image must render at a fixed size regardless of the device's text
// setting.

private struct ScaledFontModifier: ViewModifier {
    @ScaledMetric var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, relativeTo textStyle: Font.TextStyle, weight: Font.Weight, design: Font.Design) {
        self._size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

public extension View {
    /// Body text at `size`, scaling with Dynamic Type (anchored to `.body`).
    func ctBody(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo textStyle: Font.TextStyle = .body) -> some View {
        modifier(ScaledFontModifier(size: size, relativeTo: textStyle, weight: weight, design: .default))
    }

    /// Rounded display text at `size`, scaling with Dynamic Type (anchored to `.title3`).
    func ctDisplay(_ size: CGFloat, _ weight: Font.Weight = .semibold, relativeTo textStyle: Font.TextStyle = .title3) -> some View {
        modifier(ScaledFontModifier(size: size, relativeTo: textStyle, weight: weight, design: .rounded))
    }

    /// Monospaced text at `size`, scaling with Dynamic Type (anchored to `.footnote`).
    func ctMono(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo textStyle: Font.TextStyle = .footnote) -> some View {
        modifier(ScaledFontModifier(size: size, relativeTo: textStyle, weight: weight, design: .monospaced))
    }
}

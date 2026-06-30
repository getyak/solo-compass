import SwiftUI

/// `SoloMascotView` — the cartoon-girl avatar that represents Solo, the
/// traveler's companion. She lives in the bottom-right amber FAB on the
/// homepage and is the entry-point to Solo Chat.
///
/// Composition is 100% SwiftUI shape primitives (Circle, Ellipse, Path) +
/// the existing `CT` palette — no image assets, no Lottie, no SwiftPM deps.
/// The view is sized to fit comfortably inside the existing 56pt amber
/// `Circle` background, so the parent FAB's hit-target / shadow / press-ring
/// stay byte-identical.
///
/// Behaviors
/// ---------
/// - Idle breathing scale (1.0 → 1.03, 1.6s ease-in-out, infinite).
/// - Blink roughly every 4s (eye height 8 → 0 → 8 over 0.15s).
/// - Tiny ponytail sway (±3°, 2s ease-in-out, infinite).
/// - When `isPressed` flips true, a soft `sparkles` SF Symbol fades in next
///   to her cheek for ~0.45s, then fades back out.
/// - Honors `@Environment(\.accessibilityReduceMotion)`: idle/sway/blink stop
///   when motion is reduced; the press-sparkle is the only motion that stays.
///
/// The view is intentionally parameter-light: it takes an optional
/// `isPressed` so the parent FAB can drive the sparkle from its existing
/// long-press gesture without owning any of the mascot's internal state.
struct SoloMascotView: View {
    /// Driven by the parent FAB's touch-down state. When it transitions
    /// false → true, the cheek sparkle plays once.
    var isPressed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Idle animation state
    @State private var breathe: Bool = false
    @State private var sway: Bool = false
    @State private var blinkClosed: Bool = false
    @State private var sparkleVisible: Bool = false

    // Mascot is laid out inside a 44×44 box so it sits comfortably inside
    // the 56pt amber background circle with ~6pt margin all around.
    private let size: CGFloat = 44

    var body: some View {
        ZStack {
            // Cream halo behind the mascot — separates her from busy map
            // labels so she always reads as a floating button. Wider + softer
            // than the previous inner glow so the silhouette stays crisp.
            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: size + 14, height: size + 14)
                .blur(radius: 5)

            // Ponytail — a swept teardrop in sun-gold. Pushed further out
            // beyond the face circle so the silhouette unambiguously reads as
            // "girl with a low ponytail" (not just "round head") at FAB size.
            // Right-side sweep so it doesn't clip into the cluster-pin area
            // on the left of the FAB.
            ponytail
                .frame(width: 18, height: 26)
                .offset(x: size * 0.40, y: size * 0.18)
                .rotationEffect(.degrees(sway ? 8 : -2), anchor: .top)
                .animation(
                    reduceMotion ? nil :
                        .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                    value: sway
                )

            // Face (round, peach skin)
            Circle()
                .fill(skinColor)
                .overlay(
                    Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                )
                .frame(width: size * 0.78, height: size * 0.78)

            // Fringe / bangs — a soft amber arc across the top of the face.
            fringe
                .frame(width: size * 0.78, height: size * 0.78)

            // Facial features (eyes, blush, smile) stacked together so they
            // share the same anchor and don't drift with the parent scale.
            face
                .frame(width: size * 0.78, height: size * 0.78)

            // Press sparkle — only visible briefly when `isPressed` flips on.
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CT.sunGold)
                .opacity(sparkleVisible ? 1.0 : 0.0)
                .scaleEffect(sparkleVisible ? 1.0 : 0.6)
                .offset(x: size * 0.34, y: -size * 0.28)
                .animation(.easeOut(duration: 0.25), value: sparkleVisible)
                .accessibilityHidden(true)
        }
        .frame(width: size, height: size)
        .scaleEffect(reduceMotion ? 1.0 : (breathe ? 1.03 : 1.0))
        .animation(
            reduceMotion ? nil :
                .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
            value: breathe
        )
        .onAppear { startIdleAnimations() }
        .onChange(of: isPressed) { _, pressing in
            if pressing { playSparkle() }
        }
        .accessibilityHidden(true) // The parent FAB owns the a11y label.
    }

    // MARK: - Subviews

    /// Ponytail — a soft teardrop swept down-left, in sun-gold.
    private var ponytail: some View {
        TeardropShape()
            .fill(CT.sunGold)
            .overlay(
                TeardropShape().stroke(CT.sunGoldDeep.opacity(0.35), lineWidth: 0.8)
            )
    }

    /// Fringe / bangs — a soft amber arc that sits across the upper face.
    private var fringe: some View {
        FringeShape()
            .fill(CT.sunGold)
            .overlay(
                FringeShape().stroke(CT.sunGoldDeep.opacity(0.25), lineWidth: 0.5)
            )
    }

    /// Facial features composed in a single ZStack so they share the same
    /// face-circle frame.
    private var face: some View {
        ZStack {
            // Blush — two warm peach dots on the cheeks. Larger + more saturated
            // than the previous 4pt CT.accent dots so they actually read at FAB
            // size; uses a custom peach (#F4A6A6) instead of the brand red so
            // they look like blush, not warning indicators.
            HStack(spacing: 18) {
                Circle()
                    .fill(Color(red: 0.96, green: 0.65, blue: 0.65).opacity(0.75))
                    .frame(width: 6, height: 6)
                Circle()
                    .fill(Color(red: 0.96, green: 0.65, blue: 0.65).opacity(0.75))
                    .frame(width: 6, height: 6)
            }
            .offset(y: 5)

            // Eyes — two small ellipses; blink by squishing height to 0.
            HStack(spacing: 10) {
                eye
                eye
            }
            .offset(y: -2)

            // Smile — a small upward curve below the eyes.
            SmileShape()
                .stroke(CT.accent, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .frame(width: 10, height: 4)
                .offset(y: 8)
        }
    }

    private var eye: some View {
        Capsule()
            .fill(Color(red: 0.16, green: 0.10, blue: 0.06)) // warm near-black
            .frame(width: 4, height: blinkClosed ? 0.6 : 4)
            .animation(.easeInOut(duration: 0.12), value: blinkClosed)
    }

    // MARK: - Animation lifecycle

    private func startIdleAnimations() {
        guard !reduceMotion else { return }
        breathe = true
        sway = true
        scheduleNextBlink()
    }

    /// Recursive blink scheduler — fires every ~3.5–4.5s.
    private func scheduleNextBlink() {
        guard !reduceMotion else { return }
        let delay = Double.random(in: 3.5...4.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.12)) { blinkClosed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0.12)) { blinkClosed = false }
                scheduleNextBlink()
            }
        }
    }

    /// Plays the cheek sparkle once: fade-in over 0.25s, hold ~0.20s, fade-out.
    private func playSparkle() {
        sparkleVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            sparkleVisible = false
        }
    }

    // MARK: - Palette

    /// Warm peach skin tone — slightly darker than pure peach so it reads
    /// against the deep-amber background without losing the "cartoon" feel.
    private var skinColor: Color {
        Color(red: 0.99, green: 0.86, blue: 0.74)
    }
}

// MARK: - Shapes

/// A swept teardrop used for the ponytail. The narrow end points up
/// (attaches to the head), the round end swings down-left.
private struct TeardropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let bottom = CGPoint(x: rect.midX - rect.width * 0.05, y: rect.maxY)
        p.move(to: top)
        // Left curve out then down to the round tip.
        p.addQuadCurve(
            to: bottom,
            control: CGPoint(x: rect.minX - 2, y: rect.midY)
        )
        // Right curve back up to the narrow attach point.
        p.addQuadCurve(
            to: top,
            control: CGPoint(x: rect.maxX + 2, y: rect.midY - 4)
        )
        p.closeSubpath()
        return p
    }
}

/// A soft fringe / bangs arc that hugs the top of the face circle.
private struct FringeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let topLeft = CGPoint(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.18)
        let topRight = CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.minY + rect.height * 0.18)
        let dipLeft = CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.38)
        let dipMid = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.30)
        let dipRight = CGPoint(x: rect.maxX - rect.width * 0.32, y: rect.minY + rect.height * 0.38)

        p.move(to: topLeft)
        // Outer arc across the top of the face.
        p.addQuadCurve(
            to: topRight,
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.10)
        )
        // Inner zig-zag fringe edge: right → dip → mid bump → dip → left.
        p.addQuadCurve(to: dipRight, control: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.34))
        p.addQuadCurve(to: dipMid, control: CGPoint(x: rect.midX + rect.width * 0.16, y: rect.minY + rect.height * 0.42))
        p.addQuadCurve(to: dipLeft, control: CGPoint(x: rect.midX - rect.width * 0.16, y: rect.minY + rect.height * 0.42))
        p.addQuadCurve(to: topLeft, control: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.34))
        p.closeSubpath()
        return p
    }
}

/// A gentle smile curve — concave-up so the mouth turns up at the corners.
private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY + 2)
        )
        return p
    }
}

// MARK: - Preview

#if DEBUG
#Preview("SoloMascot — on amber FAB") {
    ZStack {
        Color(red: 0.13, green: 0.10, blue: 0.07).ignoresSafeArea()
        ZStack {
            Circle()
                .fill(CT.accent)
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            SoloMascotView()
        }
    }
}

#Preview("SoloMascot — pressed sparkle") {
    StatefulPreviewWrapper(false) { pressed in
        ZStack {
            Color.white.ignoresSafeArea()
            ZStack {
                Circle().fill(CT.accent).frame(width: 56, height: 56)
                SoloMascotView(isPressed: pressed.wrappedValue)
            }
            .onTapGesture {
                pressed.wrappedValue.toggle()
            }
        }
    }
}

/// Tiny helper that lets `#Preview` host a `@State` binding so we can
/// toggle `isPressed` to verify the sparkle animation.
private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}
#endif

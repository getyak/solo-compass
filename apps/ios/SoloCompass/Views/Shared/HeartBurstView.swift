import SwiftUI

/// Lightweight radial heart-particle burst fired when the user favorites an
/// experience. Driven by `trigger` (Int): each increment spawns a new burst.
/// Respects Reduce Motion — renders nothing when reduced motion is enabled.
public struct HeartBurstView: View {
    /// Increment to fire a burst. No burst on initial value (0).
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Particle: Identifiable {
        let id: Int
        let angle: Double   // radians, deterministic from index
        let color: Color
        let size: CGFloat
        let distance: CGFloat
        let delay: Double
    }

    @State private var animated = false

    // 8 particles at fixed 45° increments — no randomness needed.
    private static let particleCount = 8
    private static let colors: [Color] = [
        .red, .pink, .red, Color(red: 1, green: 0.4, blue: 0.6),
        .red, .pink, .red, Color(red: 1, green: 0.4, blue: 0.6),
    ]
    private static let sizes: [CGFloat] = [9, 7, 10, 7, 9, 8, 7, 10]
    private static let distances: [CGFloat] = [38, 32, 42, 30, 38, 34, 42, 30]
    private static let delays: [Double] = [0, 0.04, 0.02, 0.06, 0.01, 0.05, 0.03, 0.07]

    private var particles: [Particle] {
        (0..<Self.particleCount).map { i in
            Particle(
                id: i,
                angle: Double(i) / Double(Self.particleCount) * .pi * 2,
                color: Self.colors[i],
                size: Self.sizes[i],
                distance: Self.distances[i],
                delay: Self.delays[i]
            )
        }
    }

    public var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(particles) { p in
                    Image(systemName: "heart.fill")
                        .font(.system(size: p.size))
                        .foregroundStyle(p.color)
                        .opacity(animated ? 0 : 0.9)
                        .scaleEffect(animated ? 0.2 : 1.0)
                        .offset(
                            x: animated ? cos(p.angle) * p.distance : 0,
                            y: animated ? sin(p.angle) * p.distance : 0
                        )
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.65).delay(p.delay),
                            value: animated
                        )
                        .accessibilityHidden(true)
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            guard trigger > 0, !reduceMotion else { return }
            fire()
        }
    }

    private func fire() {
        animated = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
            animated = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            animated = false
        }
    }
}

#Preview("HeartBurst") {
    struct Demo: View {
        @State private var trigger = 0
        var body: some View {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                VStack(spacing: 48) {
                    ZStack {
                        Image(systemName: "heart.fill")
                            .font(.title)
                            .foregroundStyle(.red)
                        HeartBurstView(trigger: trigger)
                    }
                    Button("Tap to favorite") { trigger += 1 }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    return Demo()
}

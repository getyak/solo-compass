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
        let angle: Double   // radians, deterministic from index + trigger seed
        let color: Color
        let size: CGFloat
        let distance: CGFloat
        let delay: Double
    }

    @State private var animated = false
    @State private var resetTask: Task<Void, Never>?

    private static let baseColors: [Color] = [
        .red, .pink, .red, Color(red: 1, green: 0.4, blue: 0.6),
        .red, .pink, .red, Color(red: 1, green: 0.4, blue: 0.6),
        .red, Color(red: 1, green: 0.4, blue: 0.6),
    ]
    private static let baseSizes: [CGFloat] = [9, 7, 10, 7, 9, 8, 7, 10, 8, 9]
    private static let baseDistances: [CGFloat] = [38, 32, 42, 30, 38, 34, 42, 30, 36, 40]
    private static let delays: [Double] = [0, 0.04, 0.02, 0.06, 0.01, 0.05, 0.03, 0.07, 0.02, 0.05]

    /// Derives a deterministic seed from the trigger value for per-burst variation.
    private var burstSeed: Int { trigger &* 2654435761 }

    /// Deterministic pseudo-random float in [-1, 1] for a given index.
    private func jitter(_ index: Int) -> Double {
        let hash = (burstSeed &+ index &* 1597334677) & 0x7FFFFFFF
        return (Double(hash % 1000) / 500.0) - 1.0
    }

    /// 8 or 10 particles — varies by trigger so bursts differ visually.
    private var particleCount: Int {
        abs(burstSeed) % 3 == 0 ? 10 : 8
    }

    private var particles: [Particle] {
        let count = particleCount
        let colorOffset = abs(trigger) % Self.baseColors.count
        return (0..<count).map { i in
            let baseAngle = Double(i) / Double(count) * .pi * 2
            let angleJitter = jitter(i) * 0.35
            let sizeScale = 1.0 + jitter(i + 100) * 0.15
            let distScale = 1.0 + jitter(i + 200) * 0.15
            let colorIndex = (i + colorOffset) % Self.baseColors.count
            return Particle(
                id: i,
                angle: baseAngle + angleJitter,
                color: Self.baseColors[colorIndex],
                size: Self.baseSizes[i % Self.baseSizes.count] * sizeScale,
                distance: Self.baseDistances[i % Self.baseDistances.count] * distScale,
                delay: Self.delays[i % Self.delays.count]
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
        .onDisappear {
            resetTask?.cancel()
        }
    }

    private func fire() {
        resetTask?.cancel()
        animated = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
            animated = true
        }
        resetTask = Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
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

#Preview("HeartBurst — sequence variation") {
    struct SequenceDemo: View {
        @State private var trigger = 0
        @State private var history: [Int] = []

        var body: some View {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                VStack(spacing: 32) {
                    Text("Tap rapidly — each burst differs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ZStack {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.red)
                        HeartBurstView(trigger: trigger)
                    }
                    .frame(height: 120)
                    Button("Favorite") {
                        trigger += 1
                        history.append(trigger)
                    }
                    .buttonStyle(.borderedProminent)
                    Text("Burst #\(trigger)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        ForEach(history.suffix(5), id: \.self) { t in
                            Text("#\(t)")
                                .font(.caption2)
                                .padding(4)
                                .background(Capsule().fill(Color.red.opacity(0.15)))
                        }
                    }
                }
            }
        }
    }
    return SequenceDemo()
}

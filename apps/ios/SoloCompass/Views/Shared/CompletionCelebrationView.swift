import SwiftUI

/// One-shot confetti burst + checkmark pop overlay fired when an experience is
/// marked complete. Driven by `trigger`: each increment spawns a new burst.
/// Respects Reduce Motion: skips particles, only shows the checkmark pop.
public struct CompletionCelebrationView: View {
    let trigger: Int
    var milestone: Int? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Particle: Identifiable {
        let id: Int
        let color: Color
        let angle: Double       // radians
        let distance: CGFloat   // launch radius
        let size: CGFloat
        let isCircle: Bool
        let rotation: Double    // final spin in degrees, seeded -180...180
        let delay: Double       // stagger offset, seeded 0...0.08
        let gravity: CGFloat    // downward drift, seeded 28...46
    }

    @State private var particles: [Particle] = []
    @State private var animated = false
    @State private var checkmarkPop = false
    @State private var milestoneVisible = false

    private static let palette: [Color] = ExperienceCategory.allCases.map(\.color)

    /// Knuth multiplicative hash seed derived from trigger for per-burst variation.
    private var burstSeed: Int { trigger &* 2654435761 }

    /// Deterministic pseudo-random float in [-1, 1] for a given particle index.
    private func jitter(_ index: Int) -> Double {
        let hash = (burstSeed &+ index &* 1597334677) & 0x7FFFFFFF
        return (Double(hash % 1000) / 500.0) - 1.0
    }

    static func makeParticles(trigger: Int, count: Int = 14) -> [Particle] {
        let seed = trigger &* 2654435761
        func jitter(_ index: Int) -> Double {
            let hash = (seed &+ index &* 1597334677) & 0x7FFFFFFF
            return (Double(hash % 1000) / 500.0) - 1.0
        }
        func lerp(_ range: ClosedRange<Double>, _ t: Double) -> Double {
            range.lowerBound + (range.upperBound - range.lowerBound) * ((t + 1.0) / 2.0)
        }
        return (0..<count).map { i in
            let baseAngle = Double(i) / Double(count) * .pi * 2
            let shapeHash = (seed &+ i &* 1000003) & 0x7FFFFFFF
            return Particle(
                id: i,
                color: palette[(i + abs(trigger)) % palette.count],
                angle: baseAngle + jitter(i) * 0.3,
                distance: CGFloat(lerp(52...92, jitter(i + 50))),
                size: CGFloat(lerp(6...11, jitter(i + 100))),
                isCircle: (shapeHash & 1) == 0,
                rotation: lerp(-180...180, jitter(i + 150)),
                delay: abs(jitter(i + 200)) * 0.08,
                gravity: CGFloat(lerp(28...46, jitter(i + 250)))
            )
        }
    }

    public var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(particles) { p in
                    Group {
                        if p.isCircle {
                            Circle().fill(p.color)
                        } else {
                            Capsule().fill(p.color)
                        }
                    }
                    .frame(
                        width: p.isCircle ? p.size : p.size * 0.45,
                        height: p.isCircle ? p.size : p.size * 1.4
                    )
                    .offset(
                        x: animated ? cos(p.angle) * p.distance : 0,
                        y: animated ? sin(p.angle) * p.distance + p.gravity : 0
                    )
                    .opacity(animated ? 0 : 0.9)
                    .scaleEffect(animated ? 0.3 : 1.0)
                    .rotationEffect(.degrees(animated ? p.rotation : 0))
                    .animation(
                        .easeOut(duration: 0.8).delay(p.delay),
                        value: animated
                    )
                }
            }

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .scaleEffect(checkmarkPop ? 1.0 : 0.01)
                .opacity(checkmarkPop ? 1.0 : 0.0)
                .symbolEffect(.bounce, value: checkmarkPop)

            if let count = milestone {
                let label = count == 1
                    ? NSLocalizedString("celebration.milestone.first", comment: "First experience milestone")
                    : String(format: NSLocalizedString("celebration.milestone.count", comment: "Nth experience milestone"), count)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                    .offset(y: 36)
                    .scaleEffect(reduceMotion ? 1.0 : (milestoneVisible ? 1.0 : 0.5))
                    .opacity(milestoneVisible ? 1.0 : 0.0)
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.6),
                        value: milestoneVisible
                    )
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            guard trigger > 0 else { return }
            fire()
        }
    }

    // This view owns the completion haptic: success notification immediately,
    // soft impact ~0.12s later synced to the checkmark pop. Haptics.notify/impact
    // guard on Reduce Motion, so nothing fires when particles are also suppressed.
    private func fire() {
        particles = Self.makeParticles(trigger: trigger)
        animated = false
        checkmarkPop = false
        milestoneVisible = false

        #if canImport(UIKit)
        Haptics.notify(.success)
        UIAccessibility.post(
            notification: .announcement,
            argument: NSAttributedString(
                string: NSLocalizedString("celebration.complete.a11y", comment: "Experience completed celebration announcement"),
                attributes: [.accessibilitySpeechQueueAnnouncement: true]
            )
        )
        if let count = milestone {
            let milestoneText = count == 1
                ? NSLocalizedString("celebration.milestone.first", comment: "First experience milestone")
                : String(format: NSLocalizedString("celebration.milestone.count", comment: "Nth experience milestone"), count)
            UIAccessibility.post(
                notification: .announcement,
                argument: NSAttributedString(
                    string: milestoneText,
                    attributes: [.accessibilitySpeechQueueAnnouncement: true]
                )
            )
        }
        #endif

        withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
            checkmarkPop = true
        }
        if milestone != nil {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                milestoneVisible = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Haptics.impact(.soft)
        }

        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.8)) {
                animated = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            particles = []
            animated = false
            checkmarkPop = false
            withAnimation(.easeOut(duration: 0.2)) {
                milestoneVisible = false
            }
        }
    }
}

#Preview("Burst") {
    struct Demo: View {
        @State private var trigger = 0
        var body: some View {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                VStack(spacing: 32) {
                    Button("Fire celebration") { trigger += 1 }
                        .buttonStyle(.borderedProminent)
                    CompletionCelebrationView(trigger: trigger)
                }
            }
        }
    }
    return Demo()
}

#Preview("Reduce Motion") {
    struct Demo: View {
        @State private var trigger = 0
        var body: some View {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                VStack(spacing: 32) {
                    Button("Fire (no particles)") { trigger += 1 }
                        .buttonStyle(.borderedProminent)
                    CompletionCelebrationView(trigger: trigger)
                }
            }
        }
    }
    return Demo()
}
